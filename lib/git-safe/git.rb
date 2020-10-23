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

    def init
      execute_git_cmd("git #{git_locale} init")
    end

    def status
      execute_git_cmd("git #{git_locale} status")
    end

    def add_and_commit(commit_msg)
      execute_git_cmd("git #{git_locale} add .")
      execute_git_cmd("git #{git_locale} commit -m '#{commit_msg}'")
    end

    def last_commit_sha
      execute_git_cmd("git #{git_locale} rev-parse HEAD")
    end

    def branch_a
      execute_git_cmd("git #{git_locale} branch -a")
    end

    def checkout(branch: nil, create: false, sha: nil)
      co          = "git #{git_locale} checkout"
      create_flag = create ? ' -b' : ''
      if branch
        co = "#{co}#{create_flag} #{branch}"
      elsif sha
        co = "#{co} #{sha}"
      end
      execute_git_cmd(co)
    end

    def merge(to_merge_name)
      execute_git_cmd("git #{git_locale} merge #{to_merge_name}")
    end

    def push(remote: 'origin', branch: 'master', force: false)
      force_flag = force ? '-f ' : ''
      execute_git_cmd("git #{git_locale} push #{force_flag}#{remote} #{branch}")
    end

    def fetch
      execute_git_cmd("#{ssh_cmd}git #{git_locale} fetch")
    ensure
      safe_unlink_private_key_tmp_file
    end

    def pull(branch: 'master')
      execute_git_cmd("#{ssh_cmd}git #{git_locale} pull origin #{branch}")
    ensure
      safe_unlink_private_key_tmp_file
    end

    def clone(remote_uri, depth: nil)
      if options[:clone_command]
        execute_git_cmd(options[:clone_command].gsub(options[:clone_command_repo_dir_replace_text], work_tree))
      else
        depth_cmd = depth ? " --depth=#{depth}" : ''
        execute_git_cmd("#{ssh_cmd}git clone #{remote_uri}#{depth_cmd} #{work_tree}")
      end
    ensure
      safe_unlink_private_key_tmp_file
    end

    def git_locale
      "#{work_tree_flag} --git-dir=#{work_tree}/.git"
    end

    def work_tree_flag
      "--work-tree=#{work_tree}"
    end

    def add_remote(uri, name: 'origin')
      execute_git_cmd("git #{git_locale} remote add #{name} #{uri}")
    end

    def has_remote?
      git_config&.match(/\[remote/)
    end

    def remotes
      return [] unless has_git_config? && remote_strs = execute_git_cmd("git #{git_locale} remote -v")
      
      remote_strs.split("\n").collect do |remote_str|
        name, uri, type = remote_str.split(' ')
        { name: name,
          uri:  uri,
          type: type.gsub('(', '').gsub(')', '') }
      end
    end

    def clone_or_fetch_and_merge(source_uri, branch: 'master', remote_branch: nil, depth: nil)

    end

    def git_config
      File.read(git_config_path) if has_git_config?
    end

    def has_git_config?
      File.exists?(git_config_path)
    end

    def git_config_path
      "#{work_tree}/.git/config"
    end

    alias_method :work_tree_is_git_repo?, :has_git_config?

    def execute_git_cmd(git_cmd)
      stdout_str, stderr_str, status = Open3.capture3(git_cmd)
      raise CommandError.new("error executing '#{git_cmd}', status: #{status.exitstatus}, std_error: #{stderr_str}") unless status.exitstatus == 0

      [stdout_str, stderr_str].reject { |out| out.nil? || out.strip == '' }.join(',')
    end
  end
end