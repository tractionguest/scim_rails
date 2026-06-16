module ScimRails
  class AuthorizeApiRequest

    def initialize(searchable_attribute:, authentication_attribute:)
      @searchable_attribute = searchable_attribute
      @authentication_attribute = authentication_attribute

      raise ScimRails::ExceptionHandler::InvalidCredentials if searchable_attribute.blank? || authentication_attribute.blank?

      @search_parameter = { ScimRails.config.basic_auth_model_searchable_attribute => @searchable_attribute }
    end

    def company
      company = find_company
      authorize(company)
      company
    end

    private

    attr_reader :authentication_attribute
    attr_reader :search_parameter
    attr_reader :searchable_attribute

    def find_company
      Rails.logger.error("[SCIM_RAILS] find_company (#{ScimRails.config.basic_auth_model}): #{search_parameter}")
      @company ||= ScimRails.config.basic_auth_model.find_by!(search_parameter).tap do |company|
        Rails.logger.error("[SCIM_RAILS] find_company => #{@company}")
      end

    rescue ActiveRecord::RecordNotFound => e
      Rails.logger.error("[SCIM_RAILS] find_company ERROR: (#{e.class}) #{e} (search_parameter: #{search_parameter}) [uuids: #{Account.pluck(:uuid)}]")
      raise ScimRails::ExceptionHandler::InvalidCredentials
    end

    def authorize(authentication_model)
      authorized = ActiveSupport::SecurityUtils.secure_compare(
        authentication_model.public_send(ScimRails.config.basic_auth_model_authenticatable_attribute),
        authentication_attribute
      )
      raise ScimRails::ExceptionHandler::InvalidCredentials unless authorized
    end
  end
end
