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

    def log
      execute_git_cmd("git #{git_locale} log")
    end

    def config_set(name_values = {})
      name_values.keys.each do |key|
        execute_git_cmd("git #{git_locale} config #{key} #{name_values[key]}") if name_values[key]
      end
    end

    def config_get(name)
      execute_git_cmd("git #{git_locale} config #{name}")
    end

    def rm(remove_paths)
      execute_git_cmd("git #{git_locale} rm #{remove_paths}")
    end

    def add(add_paths)
      execute_git_cmd("git #{git_locale} add #{add_paths}")
    end

    def commit(commit_msg)
      execute_git_cmd("git #{git_locale} commit -m '#{commit_msg}'")
    end

    def add_and_commit(commit_msg)
      add('.')
      commit(commit_msg)
    end

    def last_commit_sha
      execute_git_cmd("git #{git_locale} rev-parse HEAD")
    end

    def last_commit_timestamp
      execute_git_cmd("git #{git_locale} log -1 --format=%cd ")
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

    def reset_local_to_remote(remote_name)
      execute_git_cmd("git #{git_locale} reset --hard #{remote_name}")
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

    def clone_or_fetch_and_merge(remote_uri, branch: 'master', remote_name: 'origin', depth: nil, force_fresh_clone: false, reset_to_remote: false, git_config: {})
      delete_work_tree if force_fresh_clone

      unless has_remote?
        clone(remote_uri, depth: depth)
      end

      config_set(git_config)
      fetch
      checkout(branch: branch)
      if reset_to_remote
        reset_local_to_remote("#{remote_name}/#{branch}")
      else
        merge("#{remote_name}/#{branch}")
      end
    end

    def flatten_history
      config_set(@options[:git_config])
      execute_git_cmd("git #{git_locale} checkout --orphan flattened")
      commit("Commit history flattened")
      push(remote: 'origin', branch: 'flattened:master', force: true)
    end

    def git_config
      File.read(git_config_path) if has_git_config?
    end

    def has_git_config?
      File.exist?(git_config_path)
    end

    def git_config_path
      "#{work_tree}/.git/config"
    end

    def delete_work_tree
      FileUtils.rm_rf(work_tree) if Dir.exist?(work_tree)
    end

    alias_method :work_tree_is_git_repo?, :has_git_config?

    def execute_git_cmd(git_cmd)
      stdout_str, stderr_str, status = Open3.capture3(git_cmd)
      raise CommandError.new("error executing '#{git_cmd}', status: #{status.exitstatus}, std_error: #{stderr_str}") unless status.exitstatus == 0

      [stdout_str, stderr_str].reject { |out| out.nil? || out.strip == '' }.join(',')
    end
  end
end