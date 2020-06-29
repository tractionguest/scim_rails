require 'spec_helper'

RSpec.describe ScimRails::ScimGroupsController, type: :controller do
  include AuthHelper

  routes { ScimRails::Engine.routes }
  let(:company) { create(:company) }

  describe 'index' do
    context 'without authorization' do
      before { get :index }

      it "returns scim+json content type" do
        expect(response.content_type).to eq "application/scim+json"
      end

      it "fails with no credentials" do
        expect(response.status).to eq 401
      end

      it "fails with invalid credentials" do
        request.env['HTTP_AUTHORIZATION'] = ActionController::HttpAuthentication::Basic.encode_credentials("unauthorized","123456")
        expect(response.status).to eq 401
      end
    end

    context 'with authorization' do
      before :each do
        http_login(company)
      end

      let(:user_list_length) { 3 }
      let(:user_list) { create_list(:user, user_list_length, first_name: Faker::Name.first_name, last_name: Faker::Name.last_name, company: company) }
      let(:response_body) { JSON.parse(response.body) }

      it 'returns scim+json content type' do
        get :index
        expect(response.content_type).to eq "application/scim+json"
      end

      it 'is successful' do
        get :index
        expect(response.status).to eq(200)
      end

      context 'when less than 100 existing groups' do
        let(:total_group_count) { 10 }

        let(:returned_resource) { response_body["Resources"].first }
        let!(:group_list) { create_list(:group, total_group_count, users: user_list, company: company) }

        it 'returns all results' do
          get :index
          expect(response_body.dig("schemas", 0)).to eq "urn:ietf:params:scim:api:messages:2.0:ListResponse"
          expect(response_body["totalResults"]).to eq(total_group_count)
        end

        it 'returns the correct data for members' do
          get :index
          expect(returned_resource["members"].map{ |res| res["value"] }).to match_array(Array(1..user_list_length))
        end

        context 'with filter parameters' do
          let(:search_term) { Faker::Games::Pokemon.name }
          let(:not_search_term) { search_term[0, search_term.length - 1] }
          let(:unfound_search_term) { search_term[0, search_term.length - 2] }

          let!(:group_with_search_term) { create(:group, display_name: search_term, company: company) }
          let!(:group_without_search_term) { create(:group, display_name: not_search_term, company: company) }

          it 'filters results by provided display name' do
            get :index, params: {
              filter: "displayName eq #{search_term}"
            }
            
            expect(response_body["totalResults"]).to eq(1)
            expect(response_body["Resources"].count).to eq(1)
            expect(returned_resource["displayName"]).to eq(search_term)
          end

          it 'returns no results for unfound filter parameters' do
            get :index, params: {
              filter: "displayName eq #{unfound_search_term}"
            }

            expect(response_body["totalResults"]).to eq(0)
            expect(response_body["Resources"].count).to eq(0)
          end

          it 'raises an error for undefined filter queries' do
            get :index, params: {
              filter: "nameDisplay eq will_raise_error"
            }

            expect(response.status).to eq(400)
            expect(response_body.dig("schemas", 0)).to eq("urn:ietf:params:scim:api:messages:2.0:Error")
          end
        end
      end

      context 'when more than 100 existing groups' do
        let(:total_group_count) { 150 }
        let!(:all_groups) { create_list(:group, total_group_count, users: [], company: company) }

        it 'returns a max of 100 results' do
          get :index
          expect(response_body["totalResults"]).to eq(total_group_count)
          expect(response_body["Resources"].count).to eq(100)
        end

        it 'paginates results' do
          get :index, params: {
            startIndex: 10,
            count: 125
          }

          expect(response_body["totalResults"]).to eq(total_group_count)
          expect(response_body["Resources"].count).to eq(125)
          expect(response_body.dig("Resources", 0, "id")).to eq(10)
        end

        it "paginates results by configurable scim_groups_list_order" do
          allow(ScimRails.config).to receive(:scim_groups_list_order).and_return({ created_at: :desc })
  
          get :index, params: {
            startIndex: 1,
            count: 10,
          }

          expect(response_body["totalResults"]).to eq(total_group_count)
          expect(response_body["Resources"].count).to eq(10)
          expect(response_body.dig("Resources", 0, "id")).to eq(total_group_count)
        end
      end
    end
  end

  describe 'show' do
    context "when unauthorized" do
      before { get :show, params: { id: 1 } }

      it "returns scim+json content type" do
        expect(response.content_type).to eq "application/scim+json"
      end

      it "fails with no credentials" do
        expect(response.status).to eq 401
      end

      it "fails with invalid credentials" do
        request.env['HTTP_AUTHORIZATION'] = ActionController::HttpAuthentication::Basic.encode_credentials("unauthorized","123456")
        expect(response.status).to eq 401
      end
    end

    context "when authorized" do
      before :each do
        http_login(company)
      end

      let(:user_list_length) { 3 }
      let(:group_name) { Faker::Games::Pokemon.name }

      let!(:user_list) { create_list(:user, user_list_length) } 
      let!(:group) { create(:group, display_name: group_name, users: user_list, company: company) }

      let(:returned_resource) { JSON.parse(response.body) }

      it "returns scim+json content type" do
        get :show, params: { id: 1 }

        expect(response.content_type).to eq "application/scim+json"
      end

      it "returns :not_found for invalid id" do
        get :show, params: { id: "invalid_id" }
        
        expect(response.status).to eq(404)
      end

      context "with unauthorized group" do
        let!(:new_company) { create(:company) }
        let!(:unauthorized_group) { create(:group, company: new_company) }

        it "returns :not_found for correct id but unauthorized company" do
          get :show, params: { id: unauthorized_group.id }

          expect(response.status).to eq(404)
        end
      end

      it "is successful with correct id provided" do
        get :show, params: { id: 1 }

        expect(response.status).to eq(200)
        expect(returned_resource["displayName"]).to eq(group_name)
        expect(returned_resource["members"].map{ |res| res["value"] }).to match_array(Array(1..user_list_length))
      end
    end
  end

  describe "create" do
    context "when unauthorized" do
      before { post :create }

      it "returns scim+json content type" do
        expect(response.content_type).to eq "application/scim+json"
      end

      it "fails with no credentials" do
        expect(response.status).to eq 401
      end

      it "fails with invalid credentials" do
        request.env['HTTP_AUTHORIZATION'] = ActionController::HttpAuthentication::Basic.encode_credentials("unauthorized","123456")
        expect(response.status).to eq 401
      end
    end

    context "when authorized" do
      before :each do
        http_login(company)
      end

      let(:created_group) { company.groups.first }

      let(:params) do
        {
          displayName: post_name,
          email: post_email,
          members: [],
          unconfiguredParam: post_extra_param,
          active: post_active,
        }.compact
      end

      let(:post_name) { Faker::Name.name }
      let(:post_email) { Faker::Internet.email }
      let(:post_extra_param) { nil }
      let(:post_active) { nil }

      it "returns scim+json credentials" do
        post :create, params: params
        
        expect(response.content_type).to eq("application/scim+json")
      end

      context "when all params correct" do
        it "successfully creates group" do
          expect(company.groups.count).to eq(0)
          expect(Group.count).to eq(0)

          post :create, params: params

          expect(response.status).to eq(201)

          expect(company.groups.count).to eq(1)
          expect(Group.count).to eq(1)

          expect(created_group.display_name).to eq(post_name)
          expect(created_group.email).to eq(post_email)
          expect(created_group.random_attribute).to eq(true)
        end
      end

      context "when required missing params" do
        let(:post_email) { nil }

        it "returns 422" do
          post :create, params: params

          expect(response.status).to eq(422)
          expect(company.groups.count).to eq(0)
        end
      end

      context "with extra params used" do
        let(:post_extra_param) { "unconfigured" }

        it "ignores it and creates the group" do
          post :create, params: params

          expect(response.status).to eq(201)
          expect(company.groups.count).to eq(1)
        end
      end

      context "with active param as false" do
        let(:post_active) { "false" }

        it "creates and deactivates group" do
          post :create, params: params

          expect(response.status).to eq(201)
          expect(company.groups.count).to eq(1)

          expect(created_group.active?).to eq(false)
        end
      end

      context "with conflicting groups" do
        context "when updating is allowed" do
          let(:post_email) { Faker::Internet.email + '1' }

          it "updates existing group" do
            create(:group, display_name: post_name, company: company)

            post :create, params: params

            expect(response.status).to eq(201)

            expect(company.groups.count).to eq(1)
            expect(created_group.email).to eq(post_email)
          end
        end

        context "when updating is not allowed" do
          it "returns 409 conflict" do
            allow(ScimRails.config).to receive(:scim_group_prevent_update_on_create).and_return(true)
            create(:group, display_name: post_name, company: company)

            post :create, params: params

            expect(response.status).to eq(409)
            expect(company.groups.count).to eq(1)
          end
        end
      end      
    end
  end

  describe "put update" do
    context "when unauthorized" do
      before { put :put_update, params: { id: 1 } }

      it "returns scim+json content type" do
        expect(response.content_type).to eq "application/scim+json"
      end

      it "fails with no credentials" do
        expect(response.status).to eq 401
      end

      it "fails with invalid credentials" do
        request.env['HTTP_AUTHORIZATION'] = ActionController::HttpAuthentication::Basic.encode_credentials("unauthorized","123456")
        expect(response.status).to eq 401
      end
    end

    context "when authorized" do
      before :each do
        http_login(company)
        put :put_update, params: params, as: :json
      end

      let(:original_user_list_length) { 3 }
      let(:replacement_list_length) { 2 }

      let!(:user_list) { create_list(:user, original_user_list_length, company: company) }
      let!(:target_group) { create(:group, users: user_list, company: company) }

      let!(:replacement_users) { create_list(:user, replacement_list_length, company: company) }
      let(:replacement_ids) { replacement_users.map{ |user| user[:id] }}

      let(:updated_group) { company.groups.first }
      let(:updated_user_list) { updated_group.users }

      let(:params) do
        {
          id: put_id,
          displayName: put_name,
          email: put_email,
          members: put_members,
          active: put_active,
        }.compact
      end

      let(:put_id) { target_group.id }
      let(:put_name) { Faker::Name.name }
      let(:put_email) { Faker::Internet.email }
      let(:put_members) { [] }
      let(:put_active) { true }
      
      it "returns scim+json content type" do
        expect(response.content_type).to eq("application/scim+json")
      end

      context "when group id invalid" do
        let(:put_id) { "invalid_group_id" }

        it "returns 404 not found" do
          expect(response.status).to eq(404)
        end
      end

      context "when updating non-member attributes" do
        it "successfully updates the group" do
          expect(response.status).to eq(200)

          expect(updated_group.display_name).to eq(put_name)
          expect(updated_group.email).to eq(put_email)
        end

        context "if attribute params missing" do
          let(:put_email) { nil }

          it "returns 422" do
            expect(response.status).to eq(422)
            expect(updated_user_list.length).to eq(original_user_list_length)
          end
        end
      end

      context "when handling active param" do
        context "when true" do
          it "successfully activates group" do
            expect(response.status).to eq(200)
            expect(updated_group.active?).to eq(true)
          end
        end

        context "when false" do
          let(:put_active) { false }

          it "successfully deactivates group" do
            expect(response.status).to eq(200)
            expect(updated_group.active?).to eq(false)
          end
        end

        context "when invalid" do
          let(:put_active) { "hamburger" }

          it "returns 400" do
            expect(response.status).to eq(400)
            expect(updated_user_list.length).to eq(original_user_list_length)
          end
        end
      end

      context "when handling member attributes" do
        context "with empty member list" do
          it "clears the group's member list" do
            expect(response.status).to eq(200)
            expect(updated_user_list).to be_empty
          end
        end

        context "with non-empty member lists" do
          context "when member list is unique" do
            let(:put_members) { [ { value: replacement_ids[0] }, { value: replacement_ids[1] } ] }

            it "replaces a group's members" do
              expect(response.status).to eq(200)

              expect(updated_user_list.length).to eq(replacement_list_length)
              expect(updated_user_list.map{ |user| user[:id] }).to match_array(replacement_ids)
            end
          end

          context "when member list contains duplicates" do
            let(:put_members) { [ { value: replacement_ids[0] }, { value: replacement_ids[1] }, { value: replacement_ids[1] } ] }

            it "ignores the duplicates" do
              expect(response.status).to eq(200)
              expect(updated_user_list.length).to eq(replacement_list_length)
            end
          end

          context "when 'members' missing" do
            let(:put_members) { nil }

            it "returns 400 bad request" do
              expect(response.status).to eq(400)
              expect(updated_user_list.length).to eq(original_user_list_length)
            end
          end

          context "when member list is not an array" do
            let(:put_members) { "members" }

            it "returns 400 bad request" do
              expect(response.status).to eq(400)
              expect(updated_user_list.length).to eq(original_user_list_length)
            end
          end

          context "when members list is an array but not of hashes" do
            let(:put_members) { ["member1", "member2", "member3"] }

            it "returns 400 bad request" do
              expect(response.status).to eq(400)
              expect(updated_user_list.length).to eq(original_user_list_length)
            end
          end

          context "when member list contains invalid id" do
            let(:put_members) { [ { value: "invalid_member_id" } ] }

            it "returns 404 not found" do
              expect(response.status).to eq(404)
              expect(updated_user_list.length).to eq(original_user_list_length)
            end
          end
        end
      end      
    end
  end

  describe "patch update" do
    context "when unauthorized" do
      before { patch :patch_update, params: { id: 1 } }

      it "returns scim+json content type" do
        expect(response.content_type).to eq "application/scim+json"
      end

      it "fails with no credentials" do
        expect(response.status).to eq 401
      end

      it "fails with invalid credentials" do
        request.env['HTTP_AUTHORIZATION'] = ActionController::HttpAuthentication::Basic.encode_credentials("unauthorized","123456")
        expect(response.status).to eq 401
      end
    end

    context "when authorized" do
      before :each do
        http_login(company)
        patch :patch_update, params: params, as: :json
      end

      let(:user_list_length) { 3 }

      let!(:user_list) { create_list(:user, user_list_length, company: company) }
      let!(:target_group) { create(:group, users: user_list, company: company) }

      let(:updated_group) { company.groups.first }
      let(:updated_user_list) { updated_group.users }
      let(:updated_user_ids) { updated_user_list.map{ |user| user[:id] } }

      let!(:new_user) { create(:user, company: company) }

      let(:params) do
        {
          id: patch_id,
          Operations: [
            {
              op: patch_operation,
              path: patch_path,
              value: patch_value
            }.compact
          ]
        }
      end

      let(:patch_id) { target_group.id }
      let(:patch_operation) { 'placeholder' }
      let(:patch_path) { nil }
      let(:patch_value) { nil }

      it 'returns scim+json content type' do
        expect(response.content_type).to eq("application/scim+json")
      end

      context "when group id is invalid" do
        let(:patch_id) { "invalid_id" }

        it "returns 404 not found" do
          expect(response.status).to eq(404)
        end
      end

      context "when using 'replace' operation" do
        let(:patch_operation) { 'replace' }

        let(:replacement_list_length) { 2 }
        let!(:replacement_users) { create_list(:user, replacement_list_length, company: company) }
        let(:replacement_ids) { replacement_users.map{ |user| user[:id] } }

        context "when updating non-member attributes" do
          after { expect(response.status).to eq(200) }

          context "with active param not in use" do
            subject { updated_group.display_name }

            context "when path not used" do
              let(:new_name) { Faker::Name.name }
              let(:patch_value) { { displayName: new_name } }

              it { is_expected.to eq(new_name) }
            end

            context "when path in use" do
              let(:patch_path) { "displayName" }
              let(:patch_value) { Faker::Name.name }

              it { is_expected.to eq(patch_value) }
            end
          end

          context "with active param in use" do
            subject { updated_group.active? }

            context "when path not used" do
              context "with active param set to true" do
                let(:patch_value) { { active: true } }
                it { is_expected.to eq(true) }
              end

              context "with active param set to false" do
                let(:patch_value) { { active: false } }
                it { is_expected.to eq(false) }
              end
            end

            context "when path in use" do
              let(:patch_path) { "active" }

              context "with active param set to true" do
                let(:patch_value) { true }
                it { is_expected.to eq(true) }
              end

              context "with active param set to false" do
                let(:patch_value) { false }
                it { is_expected.to eq(false) }
              end
            end
          end
        end

        context "when updating member attributes" do
          let(:patch_path) { "members" }

          context "with non-empty member list" do
            let(:patch_value) { [ { value: replacement_ids[0] }, { value: replacement_ids[1] } ] }

            it "replaces the group's member list" do
              expect(response.status).to eq(200)
              expect(updated_user_list.length).to eq(replacement_list_length)
              expect(updated_user_ids).to match_array(replacement_ids)
            end
          end

          context "with empty member list" do
            let(:patch_value) { [] }

            it "clears the group's member list" do
              expect(response.status).to eq(200)
              expect(updated_user_list).to be_empty
            end
          end
        end
      end

      context "when using 'add' operation" do
        let(:patch_operation) { 'add' }

        context "when using path" do
          context "when path set to 'members'" do
            let(:patch_path) { "members" }

            context "with valid member id" do
              let(:patch_value) { [ { value: new_user.id } ] }

              it "adds the user to the group" do
                expect(response.status).to eq(200)
                expect(updated_user_list.length).to eq(user_list_length + 1)
                expect(updated_user_ids).to include(new_user.id)
              end
            end

            context "with invalid member id" do
              let(:patch_value) { [ { value: "hamburger" } ] }

              it "returns 404 not found" do
                expect(response.status).to eq(404)
              end
            end
          end

          context "when path not set to 'members'" do
            let(:patch_path) { "cheeseburger" }

            it "returns 422 unprocessable" do
              expect(response.status).to eq(422)
            end
          end
        end

        context "when not using path" do
          context "when member list is unique" do
            let(:patch_value) { [ { value: new_user.id } ] }

            it "adds the user to the group" do
              expect(response.status).to eq(200)
              expect(updated_user_list.length).to eq(user_list_length + 1)
              expect(updated_user_ids).to include(new_user.id)
            end
          end

          context "when member list contains duplicates" do
            let(:patch_value) { [ { value: new_user.id }, { value: new_user.id } ] }

            it "only adds one of the users" do
              expect(response.status).to eq(200)
              expect(updated_user_list.length).to eq(user_list_length + 1)
              expect(updated_user_ids).to include(new_user.id)
            end
          end
        end
      end

      context "when using 'remove' operation" do
        let(:patch_operation) { 'remove' }

        let(:target_user_id) { user_list.first.id }

        context "when using only path" do
          context "with path containing valid member id" do
            let(:patch_path) { "members[value eq \"#{target_user_id}\"]" }

            it "removes member from group" do
              expect(response.status).to eq(200)
              expect(updated_user_list.length).to eq(user_list_length - 1)
              expect(updated_user_ids).to_not include(target_user_id)
            end
          end

          context "with path containing invalid member id" do
            let(:patch_path) { "members[value eq \"unknown\"]" }

            it "does not remove anything" do
              expect(response.status).to eq(200)
              expect(updated_user_list.length).to eq(user_list_length)
            end
          end

          context "without member filter" do
            let(:patch_path) { "members" }

            it "clears the group's members" do
              expect(response.status).to eq(200)
              expect(updated_user_list).to be_empty
            end
          end

          context "with unprocessable path" do
            let(:patch_path) { "unprocessable_path" }

            it "returns 422 unprocessable" do
              expect(response.status).to eq(422)
            end
          end

          context "with bad filter" do
            let(:patch_path) { "members[value eq]" }

            it "returns 422 unprocessable" do
              expect(response.status).to eq(422)
            end
          end
        end

        context "when using path and value" do
          let(:patch_path) { "members" }

          context "when given member id is valid" do
            let(:patch_value) { [{ value: target_user_id }] }

            it "removes member from group" do
              expect(response.status).to eq(200)
              expect(updated_user_list.length).to eq(user_list_length - 1)
              expect(company.groups.first.users).to_not include(target_user_id)
            end
          end

          context "when given member id is invalid" do
            let(:patch_value) { [{ value: "donut" }] }

            it "returns 404 not found" do
              expect(response.status).to eq(404)
            end
          end
        end
      end

      context "when using multiple operations" do
        let(:new_display_name) { Faker::Name.first_name }
        let(:new_email) { Faker::Internet.email }

        let(:params) do
          {
            id: target_group.id,
            Operations: [
              {
                op: "replace",
                value: {
                  email: new_email,
                  displayName: new_display_name
                }
              },
              {
                op: "remove",
                path: "members"
              },
              {
                op: "add",
                value: [
                  {
                    value: new_user.id
                  }
                ]
              }
            ]
          }
        end

        it "successfully performs all three" do
          expect(response.status).to eq(200)
          expect(updated_group.display_name).to eq(new_display_name)
          expect(updated_group.email).to eq(new_email)
          expect(updated_user_list.length).to eq(1)
          expect(updated_user_ids).to include(new_user.id)
        end
      end
    end

    describe "delete" do
      let(:company) { create(:company) }
  
      context "when unauthorized" do
        before { delete :delete, params: { id: 1 } }
  
        it "returns scim+json content type" do
          expect(response.content_type).to eq "application/scim+json"
        end
  
        it "fails with no credentials" do
          expect(response.status).to eq 401
        end
  
        it "fails with invalid credentials" do
          request.env['HTTP_AUTHORIZATION'] = ActionController::HttpAuthentication::Basic.encode_credentials("unauthorized","123456")
          expect(response.status).to eq 401
        end
      end
  
      context "when authorized" do
        before :each do
          http_login(company)
          delete :delete, params: params
        end
  
        let!(:user_list) { create_list(:user, 3, company: company) }
        let!(:group) { create(:group, users: user_list, company: company) }

        let(:params) { { id: delete_id } }

        context "with invalid id" do
          let(:delete_id) { "invalid_id" }

          it "returns 404 not found" do
            expect(response.status).to eq(404)
          end
        end
  
        context "with unauthorized group" do
          let!(:new_company) { create(:company) }
          let!(:unauthorized_group) { create(:group, company: new_company) }

          let(:delete_id) { unauthorized_group.id }
  
          it "returns 404 not found" do
            expect(response.status).to eq(404)
          end
        end

        context "with valid id" do
          let(:delete_id) { group.id }

          it "successfully deletes the group" do
            expect(response.status).to eq(204)
            expect(Group.count).to eq(0)
          end
        end
      end
    end
  end
end
