require "spec_helper"

RSpec.describe ScimRails::ScimUsersController, type: :request do
  include_context 'scim_authentication'

  let(:company) { create(:company) }

  let(:params) { {} }

  describe 'SCIM Authentication' do
    subject { response }

    context 'with valid authentication' do
      before { get '/scim_rails/scim/v2/Users', params: params, headers: valid_authentication_header }

      it { is_expected.to have_http_status :ok }
    end

    context 'without valid authentication' do
      before { get '/scim_rails/scim/v2/Users', params: params, headers: invalid_authentication_header }

      it { is_expected.to have_http_status :unauthorized }
    end
  end

  describe 'SCIM Users' do
    describe 'post' do
      let(:params) do
        {
          name: {
            givenName: "New",
            familyName: "User",
          },
          emails: [
            {
              value: "new@example.com",
            },
          ],
        }
      end

      it 'creates a new user' do
        post '/scim_rails/scim/v2/Users', params: params.to_json, headers: valid_authentication_header

        expect(request.params).to include :name
        expect(response.status).to eq 201
        expect(response.media_type).to eq "application/scim+json"
        expect(company.users.count).to eq 1
      end

      context 'when user already exists' do
        let(:first_name) { Faker::Name.first_name }
        let(:last_name) { Faker::Name.last_name }
        let(:email) { 'new@example.com' }
        let!(:user) { create(:user, first_name: first_name, last_name: last_name, company: company, email: email) }

        context 'when scim_user_prevent_update_on_create is true' do
          before do
            ScimRails.config.scim_user_prevent_update_on_create = true
          end

          after do
            ScimRails.config.scim_user_prevent_update_on_create = false
          end

          it 'does not update the existing user' do
            post '/scim_rails/scim/v2/Users', params: params.to_json, headers: valid_authentication_header

            expect(response.status).to eq 409
            expect(company.users.count).to eq 1
            expect(company.users.first.first_name).to eq first_name
            expect(company.users.first.last_name).to eq last_name
          end
        end

        context 'when scim_user_prevent_update_on_create is false' do
          before do
            ScimRails.config.scim_user_prevent_update_on_create = false
          end

          it 'returns 409 with default scim_provision_method' do
            # With the default scim_provision_method (:create!), creating a user that already
            # exists returns 409 Conflict due to uniqueness validation, regardless of
            # the scim_user_prevent_update_on_create setting.
            # To enable update-on-create behavior, configure a custom scim_provision_method.
            post '/scim_rails/scim/v2/Users', params: params.to_json, headers: valid_authentication_header

            expect(response.status).to eq 409
            expect(company.users.count).to eq 1
            expect(company.users.first.first_name).to eq first_name
            expect(company.users.first.last_name).to eq last_name
          end
        end
      end

      context 'when a name has accented characters' do
        let(:params) { { name: { givenName: "Loïc", familyName: "Poisson" }, emails: [{ value: "loic@example.com" }] } }

        it 'creates the user with the name intact' do
          post '/scim_rails/scim/v2/Users', params: params.to_json, headers: valid_authentication_header

          expect(response.status).to eq 201
          expect(company.users.first.first_name).to eq "Loïc"
        end
      end

      context 'when the body is not valid UTF-8' do
        # "Loïc" encoded as ISO-8859-1: 0xEF is not a valid UTF-8 sequence on its own.
        let(:body) { %({"name":{"givenName":"Lo\xEFc","familyName":"Poisson"},"emails":[{"value":"loic@example.com"}]}).b }

        ["application/scim+json", "application/json"].each do |content_type|
          it "returns a SCIM invalidSyntax error for #{content_type}" do
            post '/scim_rails/scim/v2/Users',
              params: body,
              headers: valid_authentication_header.merge('CONTENT_TYPE': content_type)

            expect(response.status).to eq 400
            expect(response.media_type).to eq "application/scim+json"
            expect(JSON.parse(response.body)).to eq(
              "schemas" => ["urn:ietf:params:scim:api:messages:2.0:Error"],
              "scimType" => "invalidSyntax",
              "detail" => "Request body is not valid UTF-8. SCIM requests must be UTF-8 encoded (RFC 7644 section 3.8).",
              "status" => "400"
            )
            expect(company.users.count).to eq 0
          end
        end
      end
    end

    describe 'get' do
      context 'when a query param is sent as both a string and an array' do
        # Just to check the rescue ActionController::BadRequest block does not break anything
        it 'is not reported as a non-UTF-8 request' do
          get '/scim_rails/scim/v2/Users?filter=a&filter[]=b', headers: valid_authentication_header

          expect(response.status).to eq 400
          expect(response.media_type).not_to eq "application/scim+json"
          expect(response.body).to include "Invalid query parameters: expected Array (got String) for param `filter'"
        end
      end
    end

    describe 'patch' do
      let(:resp) { patch "/scim_rails/scim/v2/Users/#{target_person.id}", params: params.to_json, headers: valid_authentication_header }
      let!(:target_person) { create(:user, company: company) }

      context 'with azure request' do
        let(:params) do
          {
            id: target_person.id,
            Operations: [
              {
                "op": "replace",
                "path": "emails[type eq \"work\"].value",
                "value": "colten_grimes@boyle.us"
              },
              {
                "op": "replace",
                "value": {
                  "userName": "frederique.halvorson@dooley.co.uk",
                  "name.givenName": "Nico",
                  "name.familyName": "Grayson",
                  "urn:ietf:params:scim:schemas:extension:enterprise:2.0:User:department": "Sample Department"
                }
              }.compact,
            ],
          }
        end

        it "updates specific Person attribute" do
          expect(resp).to eq 204
          expect(target_person.reload.first_name).to eq('Nico')
          expect(target_person.reload.department).to eq('Sample Department')
        end
      end

      context 'with multi-valued attributes in value (no filter path)' do
        let(:work_email) { 'work@example.com' }
        let(:other_email) { 'other@example.com' }
        let(:params) do
          {
            id: target_person.id,
            Operations: [
              {
                'op' => 'replace',
                'value' => {
                  'emails' => [
                    { 'type' => 'other', 'value' => other_email },
                    { 'type' => 'work', 'value' => work_email }
                  ]
                }
              }
            ]
          }
        end

        it 'maps attributes by type, not by position' do
          expect(resp).to eq 204
          target_person.reload
          expect(target_person.email).to eq(work_email)
          expect(target_person.alternate_email).to eq(other_email)
        end
      end
    end
  end
end
