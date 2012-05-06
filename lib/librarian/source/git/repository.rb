require 'open3'

require 'librarian/helpers/debug'

module Librarian
  module Source
    class Git
      class Repository

        class << self
          def clone!(environment, path, repository_url)
            path = Pathname.new(path)
            path.mkpath
            git = new(environment, path)
            git.clone!(repository_url)
            git
          end

          def bin
            @bin ||= which("git") or raise Error, "cannot find git"
          end

          private

          # Cross-platform way of finding an executable in the $PATH.
          #
          #   which('ruby') #=> /usr/bin/ruby
          #
          # From:
          #   https://github.com/defunkt/hub/commit/353031307e704d860826fc756ff0070be5e1b430#L2R173
          def which(cmd)
            exts = ENV['PATHEXT'] ? ENV['PATHEXT'].split(';') : ['']
            ENV['PATH'].split(File::PATH_SEPARATOR).each do |path|
              path = File.expand_path(path)
              exts.each do |ext|
                exe = File.join(path, cmd + ext)
                return exe if File.executable?(exe)
              end
            end
            nil
          end
        end

        include Helpers::Debug

        attr_accessor :environment, :path
        private :environment=, :path=

        def initialize(environment, path)
          self.environment = environment
          self.path = Pathname.new(path)
        end

        def git?
          path.join('.git').exist?
        end

        def default_remote
          "origin"
        end

        def clone!(repository_url)
          command = %W(clone #{repository_url} . --quiet)
          run!(command, :chdir => true)
        end

        def checkout!(reference, options ={ })
          command = %W(checkout #{reference} --quiet)
          command <<  "--force" if options[:force]
          run!(command, :chdir => true)
        end

        def fetch!(remote, options = { })
          command = %W(fetch #{remote} --quiet)
          command << "--tags" if options[:tags]
          run!(command, :chdir => true)
        end

        def reset_hard!
          command = %W(reset --hard --quiet)
          run!(command, :chdir => true)
        end

        def remote_names
          command = %W(remote)
          run!(command, :chdir => true).strip.lines.map(&:strip)
        end

        def remote_branch_names
          remotes = remote_names.sort_by(&:length).reverse

          command = %W(branch -r)
          names = run!(command, :chdir => true).strip.lines.map(&:strip).to_a
          names.each{|n| n.gsub!(/\s*->.*$/, "")}
          names.reject!{|n| n =~ /\/HEAD$/}
          Hash[remotes.map do |r|
            matching_names = names.select{|n| n.start_with?("#{r}/")}
            matching_names.each{|n| names.delete(n)}
            matching_names.each{|n| n.slice!(0, r.size + 1)}
            [r, matching_names]
          end]
        end

        def hash_from(remote, reference)
          branch_names = remote_branch_names[remote]
          if branch_names.include?(reference)
            reference = "#{remote}/#{reference}"
          end

          command = %W(rev-parse #{reference} --quiet)
          run!(command, :chdir => true).strip
        end

        def current_commit_hash
          command = %W(rev-parse HEAD --quiet)
          run!(command, :chdir => true).strip!
        end

      private

        def bin
          self.class.bin
        end

        def run!(args, options = { })
          chdir = options.delete(:chdir)
          chdir = path.to_s if chdir == true

          open3_options = { }
          open3_options[:chdir] = chdir if chdir

          command = [bin]
          command.concat(args)
          debug { "Running `#{command.join(' ')}` in #{relative_path_to(chdir || Dir.pwd)}" }
          out = Open3.popen3(*command, open3_options) do |i, o, e, t|
            raise StandardError, e.read unless (t ? t.value : $?).success?
            o.read
          end
          debug { "    ->  #{out}" } if out.size > 0
          out
        end

      end
    end
  end
end
