# Copyright 2001-2013 Rally Software Development Corp. All Rights Reserved.
##################################################################################################
#
# Plugin module for VCS connector to perform user name transformation.
#  Contains a class with logic to augment a username with a domain suffix that
#  represents a candidate Rally UserName value.
#
##################################################################################################

require "vcseif/utils/exceptions"  # for ConfigurationError, UnrecoverableException
require_relative "viscount"

##################################################################################################

class UserNameDomainAugmentLookup
   %{
        An instance of this class implements a plugin to augment a username
        used to commit a change to a VCS with a domain value supplied at 
        instantiation time. That augmented value is checked against a cache
        of valid Rally UserNames.
    }

    attr_reader :rally, :log 
    attr_reader :domain
     
    def initialize(args_hash)
        vcs_ident = args_hash['vcs_ident'] || nil
        @rally    = args_hash['rally']     || nil
        logger    = args_hash['logger']    || nil
        config    = args_hash['config']    || nil

        if @rally.nil?
            problem = "UserNameDomainLookup not provided a RallyVCSConnection instance to use"
            boomex = VCSEIF_Exceptions::UnrecoverableException.new(problem)
            raise boomex, problem
        end

        if @rally.class.name !~ /RallyVCSConnection/
            problem = "rally argument for UserNameDomainAugmentLookup initialization is not a RallyVCSConnection instance"
            boomex = VCSEIF_Exceptions::UnrecoverableException.new(problem)
            raise boomex, problem
        end

        @log = nil
        @log = logger if logger

        config.sub!(/^["']/, '')  # strip off any leading
        config.sub!(/["']$/, '')  # strip off any trailing quotes

        if config.nil? or config.empty?
            problem = "UserNameDomainAugmentLookup must have a config to identify the domain augmentation"
            confex = VCSEIF_Exceptions::ConfigurationError.new(problem)
            raise confex, problem
        end

        @domain = config
        @user_cache = @rally.getRallyUsers() # will be keyed by a Rally UserName, value is the Rally Display Name 
        if @log
            @log.debug('UserNameDomainAugmentLookup user cache populated with %d entries' % @user_cache.length)
        end
        @fritzi = ViscountIdentifritz.new(vcs_ident)
    end
        

    def lookup(committer)
        """
            Augment the committer with the domain, and return the Rally Username value associated with that
            combination if it exists in the @user_cache, otherwise return a nil.

            The augmented value, which looks like a an email address, is checked against
            a cache of valid Rally username values.  Upon detecting a match, the
            augmented username value (login@domain) is returned.
        """
        identifier = @fritzi.identify(committer.to_s)
        candidate = "%s@%s" % [identifier, @domain]
        result = nil
        result = candidate if @user_cache.include?(candidate)
        # we phrase the above as we don't care if the candidate has a display name or not, just that it exists

        if @log
            @log.debug('UserNameDomainAugmentLookup for "%s" found UserName: "%s"' % [identifier, result])
        end

        return result
    end


    def service(target)
        """
            Conventional API interface for VCSEIF plugins
        """
        return lookup(target)
    end

end
