module ConfigHelpers
  def project_fixture_path
    File.expand_path(
      File.join(File.dirname(__FILE__),'../project_fixture')
    )
  end

  def project_fixture_log_file
    File.join(project_fixture_path, 'log/haystack.log')
  end

  def project_fixture_config(env='production', initial_config={}, logger=Logger.new(project_fixture_log_file))
    Haystack::Config.new(
      project_fixture_path,
      env,
      initial_config,
      logger
    )
  end

  def start_agent(env='production')
    Haystack.config = project_fixture_config(env)
    Haystack.start
  end
end
