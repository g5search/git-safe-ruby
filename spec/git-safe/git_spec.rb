require 'spec_helper'

RSpec.describe GitSafe::Git do
  include_context 'git repo'
  let(:source_uri) { 'https://github.com/perryqh/mort_calc.git' }

  its(:work_tree) { is_expected.to eq(work_tree) }
  its(:options) { is_expected.to eq(options) }

  describe '#clone' do
    subject(:clone) { git.clone(source_uri, depth: depth) }
    let(:depth) { 1 }
    let(:std) { "Cloning into 'spec/support/working-dirs/work'" }
    let(:exit_status) { 0 }
    let(:status) { double(:status, exitstatus: exit_status) }
    before do
      allow(Open3).to receive(:capture3).and_return(['', std, status])
    end

    it 'clones the provided remote-uri' do
      expect(clone).to eq(std)
      expect(Open3).to have_received(:capture3).with("git clone #{source_uri} --depth=1 #{work_tree}")
    end

    context 'when depth provided' do
      let(:depth) { nil }
      it 'does not include depth' do
        expect(clone).to eq(std)
        expect(Open3).to have_received(:capture3).with("git clone #{source_uri} #{work_tree}")
      end
    end

    context 'when ssh file provided' do
      let(:ssh_private_key) { File.join(__dir__, '..', 'support', 'not-really-key') }
      let(:options) { { logger: ::Logger.new(STDOUT), ssh_private_key: ssh_private_key } }
      before do
        allow(git).to receive(:safe_unlink_private_key_tmp_file)
      end

      it 'sets ssh private key' do
        expect(git.ssh_private_key).to eq(ssh_private_key)
      end

      it 'sets the GIT_SSH_COMMAND' do
        expect(clone).to eq(std)
        expect(Open3).to have_received(:capture3).with("GIT_SSH_COMMAND=\"ssh -i #{ssh_private_key} -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no\" git clone #{source_uri} --depth=1 #{work_tree}")
      end

      it 'safe_unlink_private_key_tmp_file' do
        clone
        expect(git).to have_received(:safe_unlink_private_key_tmp_file)
      end
    end

    context 'when ssh string provided' do
      let(:ssh_private_key) { 'mysshkeystring' }
      let(:options) { { logger: ::Logger.new(STDOUT), ssh_private_key: ssh_private_key } }
      let(:tmp_path) { '/a/path/to/ssh/file' }
      let(:private_key_temp_file) { instance_double(Tempfile, path: tmp_path) }
      let(:ssh_tempfile) { instance_double(GitSafe::SshTempfile, private_key_temp_file: double(:tmp, path: tmp_path)) }
      before do
        allow(GitSafe::SshTempfile).to receive(:new).and_return(ssh_tempfile)
        allow(ssh_tempfile).to receive(:safe_unlink_private_key_tmp_file)
      end

      it 'sets the GIT_SSH_COMMAND' do
        expect(clone).to eq(std)
        expect(Open3).to have_received(:capture3).with("GIT_SSH_COMMAND=\"ssh -i #{tmp_path} -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no\" git clone #{source_uri} --depth=1 #{work_tree}")
      end

      it 'unlinks the tmp file' do
        clone
        expect(ssh_tempfile).to have_received(:safe_unlink_private_key_tmp_file)
      end
    end

    context 'when ssh cmd provided (gcsr). This makes more sense for clone_or_pull' do
      let(:options) do
        { clone_command:                       'gcloud source repos clone my-repo <REPO_DIR> --project=pow-play',
          clone_command_repo_dir_replace_text: '<REPO_DIR>',
          logger:                              ::Logger.new(STDOUT) }
      end

      it 'clones the provided remote-uri' do
        expect(clone).to eq(std)
        expect(Open3).to have_received(:capture3).with("gcloud source repos clone my-repo #{work_tree} --project=pow-play")
      end
    end

    context 'when error' do
      let(:exit_status) { -1 }

      it 'raises a CommandError' do
        expect { clone }.to raise_error(GitSafe::CommandError)
      end
    end
  end

  describe '#pull' do
    subject(:pull) { git.pull }

    let(:std) { "pulling'" }
    let(:exit_status) { 0 }
    let(:status) { double(:status, exitstatus: exit_status) }
    before do
      allow(Open3).to receive(:capture3).and_return(['', std, status])
    end

    context 'when branch is not provided' do
      it 'pulls from master' do
        pull
        expect(Open3).to have_received(:capture3).with("git --work-tree=#{work_tree} --git-dir=#{work_tree}/.git pull origin master")
      end
    end

    context 'when branch is provided' do
      subject(:pull) { git.pull(branch: 'staging') }

      it 'pulls from staging' do
        pull
        expect(Open3).to have_received(:capture3).with("git --work-tree=#{work_tree} --git-dir=#{work_tree}/.git pull origin staging")
      end
    end

    context 'when ssh file provided' do
      let(:ssh_private_key) { File.join(__dir__, '..', 'support', 'not-really-key') }
      let(:options) { { logger: ::Logger.new(STDOUT), ssh_private_key: ssh_private_key } }

      before do
        allow(git).to receive(:safe_unlink_private_key_tmp_file)
      end

      it 'pulls use private key' do
        pull
        expect(Open3).to have_received(:capture3).with("GIT_SSH_COMMAND=\"ssh -i #{ssh_private_key} -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no\" git --work-tree=#{work_tree} --git-dir=#{work_tree}/.git pull origin master")
      end

      it 'safe_unlink_private_key_tmp_file' do
        pull
        expect(git).to have_received(:safe_unlink_private_key_tmp_file)
      end
    end
  end

  describe '#init' do
    subject(:init) { git.init }
    it 'has a .git directory' do
      init
      expect(Dir.exist?(File.join('.git'))).to be_truthy
    end
  end

  describe '#status' do
    subject(:status) { git.status }
    before { git.init }
    it { is_expected.to match(/On branch master/) }
  end

  describe 'add and rm' do
    before do
      git.init
      add_file_to_working_dir
    end

    it 'adds file' do
      git.add(add_file_name)
      expect(git.status).to match(/new file:[\s]+#{add_file_name}/)
    end

    it 'adds and commits file' do
      git.add(add_file_name)
      git.commit('adding my-file')
      expect(git.status).to match(/working tree clean/)
      expect(git.log).to match(/adding my-file/)
    end

    it 'removes files' do
      git.add(add_file_name)
      git.commit('adding my-file')
      git.rm(add_file_name)
      expect(git.status).to match(/deleted:[\s]+#{add_file_name}/)
    end
  end

  describe '#add_and_commit' do
    before do
      git.init
      add_file_to_working_dir
    end

    it 'adds the file and commits' do
      expect(git.add_and_commit('committing my file')).to match(/1 insertion/)
    end
  end

  describe '#checkout' do
    subject(:checkout) { git.checkout(branch: 'master') }
    include_context 'repo with master and staging branches'

    context 'when branch provided' do
      it 'checks out the branch' do
        git.checkout(branch: 'staging')
        expect(git.status).to match(/On branch staging/)
        expect(File.exist?("#{work_tree}/my-staging-file.txt")).to be_truthy
      end

      it 'adds and commits files to correct branch' do
        expect(File.exist?("#{work_tree}/my-file.txt")).to be_truthy
        expect(File.exist?("#{work_tree}/my-staging-file.txt")).to be_falsey
      end
    end

    context 'when create' do
      it 'creates the provided branch' do
        git.checkout(branch: 'foo', create: true)
        expect(git.branch_a).to match(/foo/)
      end
    end

    it 'knows the last commit timestamp' do
      expect(git.last_commit_timestamp).to_not be_nil
    end

    context 'when sha provided' do
      let(:sha) do
        git.last_commit_sha
      end

      it 'checks out the provided sha' do
        git.checkout(sha: sha)
        expect(git.status).to match(/HEAD detached at #{sha[0..6]}/)
      end
    end
  end

  describe '#fetch' do
    subject(:fetch) { git.fetch }

    let(:std) { "fetching'" }
    let(:exit_status) { 0 }
    let(:status) { double(:status, exitstatus: exit_status) }
    before do
      allow(Open3).to receive(:capture3).and_return(['', std, status])
    end

    it 'fetches' do
      fetch
      expect(Open3).to have_received(:capture3).with("git --work-tree=#{work_tree} --git-dir=#{work_tree}/.git fetch")
    end

    context 'when ssh file provided' do
      let(:ssh_private_key) { File.join(__dir__, '..', 'support', 'not-really-key') }
      let(:options) { { logger: ::Logger.new(STDOUT), ssh_private_key: ssh_private_key } }

      before do
        allow(git).to receive(:safe_unlink_private_key_tmp_file)
      end

      it 'pulls use private key' do
        fetch
        expect(Open3).to have_received(:capture3).with("GIT_SSH_COMMAND=\"ssh -i #{ssh_private_key} -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no\" git --work-tree=#{work_tree} --git-dir=#{work_tree}/.git fetch")
      end

      it 'safe_unlink_private_key_tmp_file' do
        fetch
        expect(git).to have_received(:safe_unlink_private_key_tmp_file)
      end
    end
  end

  describe '#merge' do
    include_context 'repo with master and staging branches'

    it 'merges' do
      git.checkout(branch: 'master')
      expect(git.merge('staging')).to match(/my-staging-file\.txt/)
      expect(File.exist?(staging_file))
    end
  end

  describe '#push' do
    context 'defaults' do
      let(:std) { 'pushing...' }
      before do
        allow(Open3).to receive(:capture3).and_return(['', std, double(:status, exitstatus: 0)])
      end
      subject(:push) { git.push }

      it 'executes git push' do
        expect(push).to eq('pushing...')
        expect(Open3).to have_received(:capture3).with("git --work-tree=#{work_tree} --git-dir=#{work_tree}/.git push origin master")
      end

      context 'with args' do
        subject(:push) { git.push(remote: 'myorigin', branch: 'staging', force: true) }

        it 'executes git push' do
          expect(push).to eq('pushing...')
          expect(Open3).to have_received(:capture3).with("git --work-tree=#{work_tree} --git-dir=#{work_tree}/.git push -f myorigin staging")
        end
      end
    end
  end

  its(:work_tree_is_git_repo?) { is_expected.to be_falsey }
  its(:remotes) { is_expected.to eq([]) }
  its(:has_remote?) { is_expected.to be_falsey }

  describe 'remotes' do
    before { git.init }

    let(:remote) { 'https://github.com/perryqh/git-safe-ruby.git' }
    context 'with default remote name' do
      before do
        git.add_remote(remote)
      end
      its(:has_remote?) { is_expected.to be_truthy }
      its(:work_tree_is_git_repo?) { is_expected.to be_truthy }
      its(:remotes) do
        is_expected.to eq([{ name: 'origin', uri: remote, type: 'fetch' },
                           { name: 'origin', uri: remote, type: 'push' }])
      end
    end

    context 'with no remotes' do
      its(:has_remote?) { is_expected.to be_falsy }
      its(:work_tree_is_git_repo?) { is_expected.to be_truthy }
      its(:remotes) { is_expected.to eq([]) }
    end

    context 'with specified remote name' do
      before do
        git.add_remote(remote, name: 'myorig')
      end
      its(:has_remote?) { is_expected.to be_truthy }
      its(:work_tree_is_git_repo?) { is_expected.to be_truthy }
      its(:remotes) do
        is_expected.to eq([{ name: 'myorig', uri: remote, type: 'fetch' },
                           { name: 'myorig', uri: remote, type: 'push' }])
      end
    end
  end

  describe '#update_config' do
    it 'updates the config' do
      git.init
      git.config_set('user.name' => 'jimmy', 'user.email' => 'jimmy@example.com')
      expect(git.config_get('user.name')).to match(/jimmy/)
      expect(git.config_get('user.email')).to match(/jimmy@example\.com/)
    end
  end

  describe '#clone_or_fetch_and_merge' do
    let(:remote_branch) { 'origin/staging' }
    let(:branch) { 'staging' }
    let(:depth) { nil }
    subject(:clone_or_fetch_and_merge) do
      git.clone_or_fetch_and_merge(source_uri, branch: branch, depth: depth, reset_to_remote: false)
    end

    context 'when not cloned' do
      let(:std) { 'clone me' }
      let(:exit_status) { 0 }
      let(:status) { double(:status, exitstatus: exit_status) }
      before do
        allow(Open3).to receive(:capture3).and_return(['', std, status])
      end

      it 'clones' do
        clone_or_fetch_and_merge
        expect(Open3).to have_received(:capture3).with("git clone #{source_uri} #{work_tree}")
        expect(Open3).to have_received(:capture3).with("git #{git.git_locale} fetch")
        expect(Open3).to have_received(:capture3).with("git #{git.git_locale} checkout staging")
        expect(Open3).to have_received(:capture3).with("git #{git.git_locale} merge origin/staging")
      end

      context 'when already cloned' do
        it 'does not fetch' do
          allow(git).to receive(:has_remote?).and_return(true)
          git.clone_or_fetch_and_merge(source_uri, branch: 'tacos', depth: 1)
          expect(Open3).to_not have_received(:capture3).with("git clone #{source_uri} #{work_tree}")
          expect(Open3).to have_received(:capture3).with("git #{git.git_locale} fetch")
          expect(Open3).to have_received(:capture3).with("git #{git.git_locale} checkout tacos")
          expect(Open3).to have_received(:capture3).with("git #{git.git_locale} merge origin/tacos")
        end
      end

      context 'with config values' do
        before do
          allow(git).to receive(:config_set)
        end
        let(:config) { { 'user.name' => 'louis', 'user.email' => 'lo@example.com' } }

        subject(:clone_or_fetch_and_merge) do
          git.clone_or_fetch_and_merge(source_uri,
                                       branch:     branch,
                                       depth:      depth,
                                       git_config: config)
        end

        it 'sets config' do
          clone_or_fetch_and_merge
          expect(git).to have_received(:config_set).with(config)
        end
      end

      context 'with force fresh' do
        subject(:clone_or_fetch_and_merge) do
          git.clone_or_fetch_and_merge(source_uri,
                                       branch:            branch,
                                       force_fresh_clone: true)
        end

        before do
          allow(FileUtils).to receive(:rm_rf).and_call_original
        end

        context 'work_tree does exist' do
          it 'deletes the dir' do
            clone_or_fetch_and_merge
            expect(FileUtils).to have_received(:rm_rf).with(work_tree)
          end
        end

        context 'work_tree does NOT exist' do
          it 'does not delete the dir' do
            git
            FileUtils.rm_r(work_tree)
            clone_or_fetch_and_merge
            expect(FileUtils).to_not have_received(:rm_rf)
          end
        end

        context 'when reset_to_remote' do
          subject(:clone_or_fetch_and_merge) do
            git.clone_or_fetch_and_merge(source_uri, branch: branch, depth: depth, reset_to_remote: true)
          end

          it 'resets to remote' do
            allow(git).to receive(:has_remote?).and_return(true)
            clone_or_fetch_and_merge
            expect(Open3).to_not have_received(:capture3).with("git clone #{source_uri} #{work_tree}")
            expect(Open3).to have_received(:capture3).with("git #{git.git_locale} fetch")
            expect(Open3).to have_received(:capture3).with("git #{git.git_locale} checkout staging")
            expect(Open3).to have_received(:capture3).with("git #{git.git_locale} reset --hard origin/staging")
          end
        end
      end
    end
  end

  describe '#flatten_history' do
    before do
      git.init
      add_file_to_working_dir
      allow(git).to receive(:config_set) {"success"}
      allow(git).to receive(:execute_git_cmd) {"success"}
      allow(git).to receive(:commit) {"success"}
      allow(git).to receive(:push) {"success"}
    end

    subject(:flatten_history) do
      git.flatten_history
    end

    it 'performs a forced push to master from a flattened topic branch' do
      flatten_history
      expect(git).to have_received(:config_set) {"whatever"}
      expect(git).to have_received(:execute_git_cmd).with("git #{git.git_locale} checkout --orphan flattened") {"whatever"}
      expect(git).to have_received(:commit).with("Commit history flattened") {"whatever"}
      expect(git).to have_received(:push).with(remote: 'origin', branch: 'flattened:master', force: true)
    end
  end
end
