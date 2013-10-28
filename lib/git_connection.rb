# Copyright 2001-2013 Rally Software Development Corp. All Rights Reserved.

require "time"
require "socket"
require "open3"

require "vcseif/connection"       # for VCSConnection
require "vcseif/utils/exceptions" # for OperationalError

############################################################################################

#GIT command notes:
# git log
# --since=2012-09-15 18:00:00
# --date-order
# --pretty=fuller or --format=GITLOGSTYLE
# --reverse-order
# --all
# --name-status

# From:  http://git-scm.com/docs/git-log
#format:"Ident: %H%nAuthor:%cn <%ce>%nCommitted: %ci%n^^^^^^^^^^%nMessage:%s%nGitAuthor:%an <%ae> On:%ai%n%b"

#
#commit d22e5f384d852f580399380da3b47e215a03beb1
#Author:     Dave Smith <dsmith@rallydev.com>
#AuthorDate: Mon Aug 13 16:01:50 2012 -0600
#Commit:     Dave Smith <dsmith@rallydev.com>
#CommitDate: Mon Aug 13 16:01:50 2012 -0600
#
#    Rev to 0.5.1

############################################################################################

class GitConnection < VCSConnection

  attr_reader :git, :backend_version, :username_required, :password_required
  attr_reader :server, :repository_name, :uri, :debug, :localhost
  attr_accessor :max_items

  GIT_CONN_VERSION = "1.1.0"
  CS_DELIM      = "^^^^^RallyGitCSDelim^^^^^"
  MESSAGE_DELIM = "^^^^^RallyGitMessageDelim^^^^^"
  FILES_DELIM   = "^^^^^RallyGitFilesDelim^^^^^"
  GIT_LOG_FORMAT = "'#{CS_DELIM}Ident: %H%nAuthor: %ce%nCommitted: %ci%n#{MESSAGE_DELIM}%nMessage: %s%nGitAuthor: %an [%ae] On:%ai%n%b#{FILES_DELIM}'"

  def initialize(config, logger)
      super(logger)
      @git = nil
      @path_to_sshkey = nil
      internalizeConfig(config)
      @backend_version = ""
      @username_required = false
      @password_required = false
  end

  def name()
      return "Git"
  end

  def version()
      return GIT_CONN_VERSION
  end

  def getBackendVersion()
      %{
          Conform to Connection subclass protocol and provide the version of the system
          we are "connecting" to.
       }
      return @backend_version
  end

  #todo - this may be generic enough for all vcs conns to go in the parent class
  def internalizeConfig(config)
      super(config)
      @server           = config['Server'        ] || Socket.gethostname
      @repository_name  = config["RepositoryBase"] || nil
      @uri              = config["Uri"           ] || false
      @max_items        = config["MaxItems"      ] || 100
      @debug            = config["Debug"         ] || false
      @localhost = _targetServerIsLocalhost(@server)

      if !@repository_name.end_with?('.git')
          @repository_name += '/.git'
      end

      if ['False', 'false', 'No', 'no', 'Off', 'off', '0'].include?(@debug)
          @debug = false
      end
  end

  def connect()
      @log.info("Connecting to Git")
      begin
          command_vector = base_command_vector
          command_vector << 'git' << '--version'
          output = ""
          #IO.popen(command_vector) {|h| output = h.read}
          output, errors, status = Open3.capture3(command_vector.join(" "))
          if errors.length > 0
            @log.debug(errors)
            problem = "Unable to interrogate Git for version information"
            operr = VCSEIF_Exceptions::OperationalError.new(problem)
            raise operr, problem
          end
          @backend_version = output.split("\n").first
      rescue Exception => ex
          @log.debug(ex.message)
          problem = "Unable to interrogate Git for version information"
          operr = VCSEIF_Exceptions::OperationalError.new(problem)
          raise operr, problem
      end

      @log.info("Connected to Git server: %s %s" % [@server, @backend_version])
      @log.info("RepositoryBase: %s" % @repository_name)
      @log.info("Uri: %s" % @uri)
      @connected = true
      return true
  end


  def disconnect()
      """
          Just reset our git instance variable to nil
      """
      @git = nil
      @connected = false
  end

  """
      check to see if @server is localhost or not
      if we on localhost, we don't need to bother with ssh
      otherwise we have to use ssh to run git on @server
      (and use ssh keys / assume ssh key access to get there)
  """
  def base_command_vector
    command_vector = []
    if !@localhost
      command_vector << 'ssh'
      command_vector << '-i' << @sshkey_path unless @sshkey_path.nil?
      server_str = @server
      server_str = "#{@username}@#{@server}" unless @username.nil? || @username == false
      command_vector << server_str
    end
    command_vector
  end

  def getRecentChangesets(ref_time)
      """
          Obtain all Changesets created in Git at or after the ref_time parameter
          which is a Time instance
      """
      ref_time_readable = ref_time.to_s.sub('UTC', 'Z')
      ref_time_iso      = ref_time.iso8601
      ref_time_merc_iso = ref_time_iso.sub('T', ' ').sub('Z', '')
      pending_operation = "Detecting recently added Git Changesets (added on or after %s)"
      @log.info(pending_operation % ref_time_readable)

      changeset_info = runLogCommand(@server, @username, @password,
                                     @repository_name, ref_time_merc_iso)

      if @debug
          File.open('git.rev.hist', 'w') {|f| f.write(changeset_info)}
      end

      chunks = _changesetChunks(changeset_info) || []
      changesets = chunks.collect { |cset_info| GitChangeset.new(cset_info) }

      log_msg = "  %d recently added Git Changesets detected"
      @log.info(log_msg % changesets.length)
      changesets.each {|cset| @log.debug(cset.details())}
      if not changesets.empty?
         oldest_changeset = changesets.first
         last_changeset   = changesets.last
         if changesets.length > 1
            @log.info("Date of oldest Git commit in chunk: #{oldest_changeset.commit_timestamp}")
         end
         @log.info("Date of latest Git commit in chunk: #{last_changeset.commit_timestamp}")
      end

      return changesets
  end


  private
  def _changesetChunks(payload)
      chunks = payload.split(CS_DELIM)
      num_items = chunks.length < @max_items? chunks.length : @max_items
      return chunks[1..num_items]
  end


  def runLogCommand(server, user, password, repo, ref_time)
      """
          ref_time comes in as ISO-8601-like format (YYYY-mm-dd HH:MM:SS)
      """
      #log_cmd = "git log --all --after=2012-09-15T18:00:00 --date-order --reverse --format=GITLOGSTYLE --name-status"

      since_time = DateTime.parse(ref_time)

      since_time_spec = "--since=%s" % since_time.iso8601

      log_options = ['--all' , since_time_spec,
                     '--date-order',   '--reverse',
                     "--format=\"#{GIT_LOG_FORMAT}\"",
                     "--encoding=UTF-8", "--name-status"
                    ]
      #command_vector = base_command_vector
      log_command_vector = []
      log_command_vector << 'git' << "--git-dir=\"#{repo}\"" << 'log'
      log_options.each { |lopt| log_command_vector << lopt }

      command_vector = base_command_vector
      command_vector << "#{log_command_vector.join(" ")}"
      @log.debug(command_vector.join(" "))
      #output = "" and IO.popen(command_vector) { |h| output = h.read() }
      output, errors, status = Open3.capture3(command_vector.join(" "))
      #puts "cmd is #{command_vector.join(" ")} \noutput is #{output} \nerrs-#{errors.length}length\n#{errors}"

      exit_code = status.to_s.strip.split(' ').pop
      if exit_code.to_i > 0
          problem = "git log command error detected: %s, exit code: %s" % [errors, exit_code]
          @log.error(problem)
          operr = VCSEIF_Exceptions::OperationalError.new(problem)
          raise operr, problem
      end

      return output
  end

end

##############################################################################################

class GitChangeset
  attr_reader :ident, :node, :rev_num, :commit_timestamp, :offset_secs
  attr_accessor :author, :humanz_date
  attr_reader :message
  attr_reader :adds, :mods, :dels

  def initialize(log_text)
      @node  = nil
      @ident = nil
      @rev_num = nil

      @author = nil
      @commit_timestamp = nil
      @offset_secs      = 0
      @humanz_date      = nil
      @message = nil

      @adds = []
      @mods = []
      @dels = []

      _extractFields(log_text)
  end

  """
      You'll get a multiline block of text that looks like:
       >>CS_DELIM<<
          Ident: 671d7258c851bd6cf76d817da4e6be1920c93dab
          Author:Dave Smith <dsmith@rallydev.com>
          Committed: 2012-08-30 20:34:58 -0600
       >>MESSAGE_DELIM<<
          Message:Rev to 0.5.2, small cleanup on readme
          GitAuthor:Dave Smith <dsmith@rallydev.com> On:2012-08-30 20:34:58 -0600

       >>FILES_DELIM<<
          M       README.rdoc
          M       lib/rally_api/rally_json_connection.rb
          M       lib/rally_api/version.rb

  """
  private
  def _extractFields(text_block)
    top_bottom = text_block.split(GitConnection::MESSAGE_DELIM)
    message_and_files = top_bottom[1].split(GitConnection::FILES_DELIM)
    message_lines = message_and_files[0]
    file_lines   = message_and_files[1].split("\n")

    @message = message_lines.split('Message: ')[1]

    log_lines = top_bottom[0].split("\n")
    ident_line       = log_lines[0]
    author_line      = log_lines[1]
    committed_line   = log_lines[2]
    ident_info = ident_line.split('Ident: ')[1]
    @ident = @rev_num = ident_info
    @author = author_line.split('Author: ')[1]

    committed_value = committed_line.split("Committed: ")[1]
    @commit_timestamp = DateTime.parse(committed_value).new_offset(0).iso8601

    file_lines.each do |fline|
      next if fline.nil? || fline.length == 0
      action, file_name = fline.strip().split("\t", 2)
      @adds << file_name if action == 'A'
      @mods << file_name if action == 'M'
      @dels << file_name if action == 'R'
    end
  end

  public
  def details()
      ident      = "Ident: %s-%s"     % [@rev_num, @node]
      author     = "Author: %s"       %  @author
      committed  = "Comitted: %s.%s"  % [@commit_timestamp, @offset_secs]
      pepul_date = "ISO8601-Date: %s" %  @humanz_date
      message    = "Message: %s"      %  @message
      elements = [ident, author, committed, pepul_date, message]
      adds = @adds.collect {|a| '    A %s' % a}.join("\n") if not @adds.empty?
      mods = @mods.collect {|m| '    M %s' % m}.join("\n") if not @mods.empty?
      dels = @dels.collect {|d| '    D %s' % d}.join("\n") if not @dels.empty?
      elements << adds if not @adds.empty?
      elements << mods if not @mods.empty?
      elements << dels if not @dels.empty?
      elements << ""
      pill = elements.join("\n")
      return pill
  end

end
    

