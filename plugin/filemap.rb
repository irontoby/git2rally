# Copyright 2001-2013 Rally Software Development Corp. All Rights Reserved.

##################################################################################################
#
# Plugin module for VCS connector to perform user name mappings.
#  Contains a class with logic to match an identifier 
#   to a Rally user name listed in a textfile
#
##################################################################################################

require "vcseif/utils/exceptions" # for ConfigurationError
require_relative "viscount"       # for ViscountIdentifritz

##################################################################################################

#for entries that look like |Name Surname <whomever@somewhere.org>|
COMPOUND_IDENT_PATTERN     = Regexp.compile("^\s*(?<ident>[^<]+)\s+<(?<email_addr>[^@]+@.+)>\s*$")
# for entries that look like |Name Surname whomever@somewhere.org|
ALT_COMPOUND_IDENT_PATTERN = Regexp.compile("^\s*(?<ident>.+)\s+(?<email_addr>[^@]+@[^ ]+)\s*$")

##################################################################################################

class FileBasedUserNameLookup
    """
        An instance of this class implements a plugin to provide the ability to
        map identifiers to Rally user name values where these mappings are contained
        in a text file.

        The VCS connector obtains an instance of this class at connector initialization time,
        providing arguments of:
            a config dict that identifies the filename to be used, 
            and separator char that partitions the VCS identifier from the Rally UserName value
            in the file
    """

    attr_reader :log

    def initialize(kwarg)
        """
            Instantiator must provide a string for the vcs_ident keyword that identifies the
            VCS system from which the candidate committer value originated from.
            In some cases the VCS system provides a committer string that is compound, ie.,
            it has both a committer identifier and a committer email address, while other VCS
            systems provide only a committer identifier as a single value.
            Instantiator must provide a config containing the elements that will identify
            the target file and the separator char. 
            A logger argument can also be provided, which for the purposes of this implementation
            will result in DEBUG log messages being generated for this method and the lookup method.
        """
        vcs_ident = kwarg['vcs_ident'] || nil
        config    = kwarg['config']    || nil
        logger    = kwarg['logger']    || nil

        @log = nil
        @log = logger if logger

        if config.nil? or config.empty?
            problem = "FileBasedUserNameLookup must have a config to identify file and sep char"
            confex  = VCSEIF_Exceptions::ConfigurationError.new(problem)
            raise confex, problem
        end

        if config.count(',') != 1
            problem = "FileBasedUserNameLookup config must be in format of 'filename,sepchar'"
            confex  = VCSEIF_Exceptions::ConfigurationError.new(problem)
            raise confex, problem
        end
        filename, sepchar = config.split(',').collect {|token| token.strip()}[0...2] 
        # if the sepchar is quoted, stript the quoting...
        if !sepchar.nil? and !sepchar.empty? and sepchar.length == 3 and sepchar[0] == sepchar[2] and ['"', "'"].include?(sepchar[0])
            sepchar = sepchar[1]
        end
        if not @log.nil?
            @log.debug('Filename: |%s|  sepchar: |%s|' % [filename, sepchar])
        end
        if filename.empty?
            problem = "FileBasedUserNameLookup filename portion of config is empty"
            confex  = VCSEIF_Exceptions::ConfigurationError.new(problem)
            raise confex, problem
        end
        if sepchar.nil? or sepchar.empty?  or sepchar.length != 1
            problem =  "FileBasedUserNameLookup sepchar portion of config must be "
            problem << "single character or quoted single character value"
            confex  = VCSEIF_Exceptions::ConfigurationError.new(problem)
            raise confex, problem
        end
##
# look for filename in '.', './configs' and in '#{installation_base}/configs'
##
        installation_base = File.expand_path(File.join(File.dirname(__FILE__), '..'))
        installation_configs_dir = "%s/configs" % installation_base
        hit = ['.', './configs', installation_configs_dir].select {|dir| File.exists?("#{dir}/#{filename}")}
        if hit.nil? or hit.empty?
            problem = "FileBasedUserNameLookup target filename '%s' not found in current directory or in configs or installation configs directories" % filename
            confex  = VCSEIF_Exceptions::ConfigurationError.new(problem)
            raise confex, problem
        end
        dir = hit.first
        file_path = "#{dir}/#{filename}"
        if not File.file?(file_path)
            problem = "FileBasedUserNameLookup filename target '%s' not found or is not a file" % file_path
            confex  = VCSEIF_Exceptions::ConfigurationError.new(problem)
            raise confex, problem
        end
        if File.size(file_path) == 0
            problem = "FileBasedUserNameLookup filename target '%s' references an empty file" % file_path
            confex  = VCSEIF_Exceptions::ConfigurationError.new(problem)
            raise confex, problem
        end

        populateLookupTable(file_path, sepchar)
        if @lkup_run.length == 0
          problem = "No useful entries detected in your #{file_path} file for mapping user names"
          confex = VCSEIF_Exceptions::ConfigurationError.new(problem)
          raise confex, problem
        end
        if @log
            @log.debug('FileBasedUserNameLookup lookup table populated with %d entries' % @lkup_run.length)
        end
##
##    puts "about to obtain a ViscountIdentifritz instance with vcs_ident value of |#{vcs_ident}|"
##
        @fritzi = ViscountIdentifritz.new(vcs_ident)
    end
        

    def service(target)
        return lookup(target)
    end


    def lookup(committer)
        """
            Attempt to match up the given committer to a Rally UserName 
            deconstructing the committer value according the rules of the VCS system
            from whence it originated into a value that would appear in the mapping file
            on the left side and consulting our internal lookup table to see if it has 
            an association with a Rally UserName (given in the mapping file as right side values)
            If there is a match, the Rally User UserName attribute of the matched User item is
            returned.  Otherwise, a nil is returned.
        """
##
##        print "FileBasedUserNameLookup.lookup called with committer parm: |%s|" % committer
##
        identifier = @fritzi.identify(committer)
##
##        print "FileBasedUserNameLookup.lookup committer --> identifier: |%s|" % identifier
##
        result = @lkup_run[identifier] || nil
        if @log
            if result
                @log.debug('for "%s"  (%s) =--> "%s"' % [committer, identifier, result])
            else
                @log.debug('for "%s"  (%s) did not match any entries' % [committer, identifier])
            end
        end
        return result

    end


    private
    def populateLookupTable(filename, sepchar)
        """
            filename should have content that looks like:
               vcs_identifier sepchar rally_user_name  
               bob : bobby@snoozer.org
               ali : alienag@deepspace.com
               ...
            fill the @lkup_run cache keyed by vcs_identifier with the rally_user_name as value
        """
        content = []
        begin
            File.open(filename, 'r') do |mf| 
                content = mf.readlines().collect {|line| line.strip()}
            end
        rescue Exception => ex
            raise StandardError, 'Unable to open and read %s: %s'% [filename, ex.message]
        end

        plausible_entries = content.select {|line| line =~ /#{sepchar}/}
        if plausible_entries.length == 0
          problem = "No valid entries found in #{filename}, consult the user guide for how to construct a properly formatted user map file"
          confex = VCSEIF_Exceptions::ConfigurationError.new(problem)
          raise confex, problem
        end

        poor_entries = plausible_entries.select {|line| line.count(sepchar) > 1}
        if poor_entries.length > 0
          problem = "#{poor_entries.length} entries found in #{filename} with multiple separator characters (#{sepchar})"
          confex = VCSEIF_Exceptions::ConfigurationError.new(problem)
          raise confex, problem
        end

        # left side is the VCS identifier
        # right side is the Rally UserName
        @lkup_run = {}  # lookup rally user name 
        for entry in content do
            next if entry.strip().empty? or entry.length < 6 # just skip blatantly erroneous entries
            next if entry.strip().start_with?('#')
            if entry.count(sepchar) < 1
                @log.warning("crufty entry: |%s| ignored, follow the proper format Luke!" % entry)
                next
            end
            vcs_ident, rally_user_name = entry.split(/#{sepchar}/, 2).collect { |token| token.strip}
            if !vcs_ident.empty? and !rally_user_name.empty?  # can't be blank on either side
              if @lkup_run.has_key?(vcs_ident)
                prior_value = @lkup_run[vcs_ident]
                situation = "A prior entry of |#{vcs_ident}| -> |#{prior_value}| will be replaced with |#{vcs_ident}| -> |#{rally_user_name}|"
                @log.warn(situation)
              end
              @lkup_run[vcs_ident] = rally_user_name
              if @log
                  @log.debug("|%s| --> |%s|" % [vcs_ident, rally_user_name])
              end
            else
              @log.error("invalid entry |%s| --> |%s| one or both of the values is empty" % [vcs_ident, rally_user_name])
            end
        end
    end

end
