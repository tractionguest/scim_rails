# Be sure to restart your server when you modify this file.

# Rails 7+ does not include sprockets by default, so we need to check if assets config exists
if Rails.application.config.respond_to?(:assets)
  # Version of your assets, change this if you want to expire all your assets.
  Rails.application.config.assets.version = '1.0'

  # Add additional assets to the asset load path
  # Rails.application.config.assets.paths << Emoji.images_path

  # Precompile additional assets.
  # application.js, application.css, and all non-JS/CSS in app/assets folder are already added.
  # Rails.application.config.assets.precompile += %w( search.js )
end
