# frozen_string_literal: true

module ScimRails
  class << self
    def configure
      yield config
    end

    def config
      @config ||= Config.new
    end
  end

  # Class containing configuration of ScimRails
  class Config
    ALGO_NONE = "none"

    attr_writer \
      :basic_auth_model,
      :mutable_user_attributes_schema,
      :scim_users_model

    attr_accessor \
      :basic_auth_model_authenticatable_attribute,
      :basic_auth_model_searchable_attribute,
      :mutable_user_attributes,
      :on_error,
      :queryable_user_attributes,
      :scim_users_list_order,
      :scim_users_scope,
      :scim_user_prevent_update_on_create,
      :signing_secret,
      :signing_algorithm,
      :user_attributes,
      :user_deprovision_method,
      :user_reprovision_method,
      :user_schema

    # TractionGuest Added Accessors
    attr_accessor \
      :mutable_group_attributes,
      :mutable_user_attributes_schema,
      :mutable_group_attributes_schema,
      :queryable_group_attributes,
      :scim_groups_list_order,
      :scim_users_model,
      :scim_groups_model,
      :scim_groups_scope,
      :scim_group_member_scope,
      :scim_group_prevent_update_on_create,
      :group_deprovision_method,
      :group_reprovision_method,
      :group_schema,
      :group_member_schema,
      :group_attributes,
      :custom_user_attributes,
      :custom_group_attributes,
      :before_scim_response,
      :after_scim_response,
      :scim_attribute_type_mappings,
      :config_schema,
      :resource_user_schema,
      :resource_group_schema,
      :retrievable_user_schema,
      :retrievable_group_schema

    def initialize
      @basic_auth_model = "Company"
      @scim_users_list_order = :id
      @scim_users_model = "User"
      @signing_algorithm = ALGO_NONE
      @user_schema = {}
      @user_attributes = []

      # TractionGuest values
      @scim_groups_list_order = :id
      @group_schema = {}
      @group_attributes = []
      @custom_user_attributes = {}
      @custom_group_attributes = {}
    end

    def mutable_user_attributes_schema
      @mutable_user_attributes_schema || @user_schema
    end

    def basic_auth_model
      @basic_auth_model.constantize
    end

    def scim_users_model
      @scim_users_model.constantize
    end

    def scim_groups_model
      @scim_groups_model.constantize
    end
  end
end
