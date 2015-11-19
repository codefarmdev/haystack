require 'haystack'

class HaystackGenerator < Rails::Generators::Base
  EXCLUDED_ENVIRONMENTS = ['test'].freeze

  source_root File.expand_path('../templates', __FILE__)
  desc 'Generate a config file for Haystack'

  def copy_config_file
    template_file = 'haystack.yml'
    destination_file = File.join('config', template_file)
    if File.exists?(destination_file)
      say_status(:error, 'Looks like you already have a config file', :red)
    else
      template(template_file, destination_file)
      # add_haystack_require_for_capistrano
      check_push_api_key
    end
  end

  protected

  def add_haystack_require_for_capistrano
    deploy_file = File.expand_path(File.join('config', 'deploy.rb'))
    cap_file = File.expand_path('Capfile')
    if [deploy_file, cap_file].all? { |file| File.exists?(file) }
      file_contents = File.read(deploy_file)
      if (file_contents =~ /require (\'|\").\/haystack\/capistrano/).nil?
        append_to_file deploy_file, "\nrequire 'haystack/capistrano'\n"
      end
    else
      say_status :info, "No capistrano setup detected! Did you know you can "\
        "use the Haystack CLI to notify Haystack of deployments?", :yellow
      say_status "", "Run the following command for help:"
      say_status "", "haystack notify_of_deploy -h"
    end
  end

  def config
    Haystack::Config.new(
      Rails.root,
      'development'
    )
  end

  def check_push_api_key
    auth_check = ::Haystack::AuthCheck.new(config, Haystack.logger)
    status, result = auth_check.perform_with_result
    if status == '200'
      say_status :success, result
    else
      say_status :error, result, :red
    end
  end

  private

  def environments
    @environments ||= Dir.glob(
      File.join(%w(. config environments *.rb))
    ).map { |o| File.basename(o, ".rb") }.sort - EXCLUDED_ENVIRONMENTS
  end
end
