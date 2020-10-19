require 'open3'

module GitSafe
  class Git
    include PrivateKeyFile

    attr_reader :options, :work_tree, :ssh_private_key, :logger

    def initialize(work_tree, options)
      @work_tree       = work_tree
      @options         = options
      @ssh_private_key = options[:ssh_private_key]
      @logger          = options[:logger]
      FileUtils.mkdir_p(work_tree)
    end

    def clone(remote_uri, depth: nil)
      depth_cmd = depth ? " --depth=#{depth}" : ''
      execute_git_cmd("#{ssh_cmd}git clone #{remote_uri}#{depth_cmd} #{work_tree}")
    ensure
      safe_unlink_private_key_tmp_file
    end

    def execute_git_cmd(git_cmd)
      stdout_str, stderr_str, status = Open3.capture3(git_cmd)
      raise CommandError.new("error executing '#{git_cmd}', status: #{status.exitstatus}, std_error: #{stderr_str}") unless status.exitstatus == 0

      [stdout_str, stderr_str].reject { |out| out.nil? || out.strip == '' }.join(',')
    end
  end
end