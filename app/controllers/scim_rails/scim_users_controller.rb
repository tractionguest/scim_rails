module ScimRails
  class ScimUsersController < ScimRails::ApplicationController
    def index
      ScimRails.config.before_scim_response.call(request.params) unless ScimRails.config.before_scim_response.nil?

      if params[:filter].present?
        query = ScimRails::ScimQueryParser.new(params[:filter])

        users = @company
          .public_send(ScimRails.config.scim_users_scope)
          .where(
            "#{ScimRails.config.scim_users_model.connection.quote_column_name(query.user_attribute)} #{query.operator} ?",
            query.parameter
          )
          .order(ScimRails.config.scim_users_list_order)
      else
        users = @company
          .public_send(ScimRails.config.scim_users_scope)
          .order(ScimRails.config.scim_users_list_order)
      end

      counts = ScimCount.new(
        start_index: params[:startIndex],
        limit: params[:count],
        total: users.count
      )

      ScimRails.config.after_scim_response.call(users, "RETRIEVED") unless ScimRails.config.after_scim_response.nil?

      json_scim_response(object: users, counts: counts)
    end

    def create
      ScimRails.config.before_scim_response.call(request.params) unless ScimRails.config.before_scim_response.nil?

      if ScimRails.config.scim_user_prevent_update_on_create
        user = @company.public_send(ScimRails.config.scim_users_scope).create!(permitted_user_params)
      else
        username_key = ScimRails.config.queryable_user_attributes[:userName]
        find_by_username = Hash.new
        find_by_username[username_key] = permitted_user_params[username_key]
        user = @company
          .public_send(ScimRails.config.scim_users_scope)
          .find_or_create_by(find_by_username)
        user.update!(permitted_user_params)
      end
      update_status(user) unless params[:active].nil?

      ScimRails.config.after_scim_response.call(user, "CREATED") unless ScimRails.config.after_scim_response.nil?

      json_scim_response(object: user, status: :created)
    end

    def show
      ScimRails.config.before_scim_response.call(request.params) unless ScimRails.config.before_scim_response.nil?

      user = @company.public_send(ScimRails.config.scim_users_scope).find(params[:id])

      ScimRails.config.after_scim_response.call(user, "RETRIEVED") unless ScimRails.config.after_scim_response.nil?

      json_scim_response(object: user)
    end

    def put_update
      ScimRails.config.before_scim_response.call(request.params) unless ScimRails.config.before_scim_response.nil?

      user = @company.public_send(ScimRails.config.scim_users_scope).find(params[:id])
      update_status(user) unless put_active_param.nil?
      user.update!(permitted_user_params)

      ScimRails.config.after_scim_response.call(user, "UPDATED") unless ScimRails.config.after_scim_response.nil?

      json_scim_response(object: user)
    end

    def patch_update
      ScimRails.config.before_scim_response.call(request.params) unless ScimRails.config.before_scim_response.nil?

      user = @company.public_send(ScimRails.config.scim_users_scope).find(params[:id])

      params["Operations"].each do |operation|
        raise ScimRails::ExceptionHandler::UnsupportedPatchRequest unless ["replace", "add", "remove"].include?(operation["op"].downcase)

        path_params = extract_path_params(operation)
        changed_attributes = permitted_params(path_params || operation["value"], "User").merge(get_multi_value_attrs(operation))

        user.assign_attributes(changed_attributes.compact)

        active_param = extract_active_param(operation, path_params)
        status = patch_status(active_param)

        next if status.nil?

        provision_method = status ? ScimRails.config.user_reprovision_method : ScimRails.config.user_deprovision_method
        user.public_send(provision_method)
      end

      user.save!

      ScimRails.config.after_scim_response.call(user, "UPDATED") unless ScimRails.config.after_scim_response.nil?

      json_scim_response(object: user)
    end

    def delete
      ScimRails.config.before_scim_response.call(request.params) unless ScimRails.config.before_scim_response.nil?

      user = @company.public_send(ScimRails.config.scim_users_scope).find(params[:id])
      user.update!(ScimRails.config.custom_user_attributes)

      user.destroy

      ScimRails.config.after_scim_response.call(user, "DELETED") unless ScimRails.config.after_scim_response.nil?

      json_scim_response(object: nil, status: :no_content)
    end

    private

    def get_multi_value_attrs(operation)
      schema_hash = contains_square_brackets?(operation["path"]) ? multi_attr_type_to_value(process_filter_path(operation)) : {}
    end

    def permitted_user_params
      permitted_params(params, "User").merge(multi_attr_type_to_value(params))
    end

    def find_value_for(attribute)
      params.dig(*path_for(attribute))
    end

    # `path_for` is a recursive method used to find the "path" for
    # `.dig` to take when looking for a given attribute in the
    # params.
    #
    # Example: `path_for(:name)` should return an array that looks
    # like [:names, 0, :givenName]. `.dig` can then use that path
    # against the params to translate the :name attribute to "John".

    def path_for(attribute, object = ScimRails.config.mutable_user_attributes_schema, path = [])
      at_path = path.empty? ? object : object.dig(*path)
      return path if at_path == attribute

      case at_path
      when Hash
        at_path.each do |key, value|
          found_path = path_for(attribute, object, [*path, key])
          return found_path if found_path
        end
        nil
      when Array
        at_path.each_with_index do |value, index|
          found_path = path_for(attribute, object, [*path, index])
          return found_path if found_path
        end
        nil
      end
    end

    def update_status(user)
      user.public_send(ScimRails.config.user_reprovision_method) if active?
      user.public_send(ScimRails.config.user_deprovision_method) unless active?
    end

    def active?
      active = put_active_param
      active = patch_active_param if active.nil?

      case active
      when true, "true", 1
        true
      when false, "false", 0
        false
      else
        raise ActiveRecord::RecordInvalid
      end
    end

    def put_active_param
      params[:active]
    end

    def patch_active_param
      handle_invalid = lambda do
        raise ScimRails::ExceptionHandler::UnsupportedPatchRequest
      end

      operations = params["Operations"] || {}

      valid_operation = operations.find(handle_invalid) do |operation|
        valid_patch_operation?(operation)
      end

      valid_operation.dig("value", "active")
    end

    def valid_patch_operation?(operation)
      operation["op"].casecmp("replace") &&
        operation["value"] &&
        [true, false].include?(operation["value"]["active"])
    end
  end
end
