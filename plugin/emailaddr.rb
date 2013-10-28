# Copyright 2001-2013 Rally Software Development Corp. All Rights Reserved.

##################################################################################################
#
# Plugin module for VCS connector to perform user name extraction.
#  Contains a class with logic to extract the the email portion of the commit Author,
#   The email portion is used as the Rally Username
#
##################################################################################################

require "vcseif/utils/exceptions"  # for ConfigurationError, UnrecoverableException

##################################################################################################

class EmailAddressAsRallyUser
    %{
        An instance of this class implements a plugin to extract the email address component
        of the commit Author which is used as the Rally Username value.

        The VCS connector obtains an instance of this class at connector initialization time,
        providing an argument of a "connected" RallyAPI::RallyRestJson instance.
     }

    # for entries that are just the email address like |festus-x2-jager@mooch1_and_4more-kore.com|
    EMAIL_ADDRESS_PATTERN = Regexp.compile("[[:alnum:]]+.*[[:alnum:]]@[[:alnum:]]+.*\..*[[:alnum:]]")

    # for entries that look like |Name Surname <whomever@somewhere.org>|  
    COMPOUND_IDENT_PATTERN     = Regexp.compile("^\s*(?<ident>[^<]+)\s+<(?<email_addr>[^@]+@.+)>\s*$")

    # for entries that look like |Name Surname whomever@somewhere.org|
    ALT_COMPOUND_IDENT_PATTERN = Regexp.compile("^\s*(?<ident>.+)\s+(?<email_addr>[^@]+@[^ ]+)\s*$")

    attr_reader :rally, :log 
    attr_reader :user_cache

    def initialize(kwarg)
        """
            Instantiator must provide a Ruby Hash argument with the following 
            key => value mappings (some of which are required, some are optional):  

                'vcs_ident' =>  a String that identifies the VCS system from which 
                                the candidate committer value originated  (required)

                'config'    =>  a String containing one or more Rally User entity attribute
                                names that will be assembled to provide match targets on
                                each extraction attempt (required)

                'rally'     =>  a RallyRestJson instance(required)

                'logger'    =>  a RallyLogger instance (or other logger instance) which can
                                respond to a debug message (method call) and emit log messages
                                constructed in thid implementation (optional)

            In some cases the VCS system provides a committer string that is compound, ie.,
            it has both a committer identifier and a committer email address, while other VCS
            systems provide only a committer identifier as a single value.
        """
        vcs_ident = kwarg['vcs_ident'] || nil
        rally     = kwarg['rally']     || nil
        logger    = kwarg['logger']    || nil
        config    = kwarg['config']    || nil
##
##  puts "EmailAddressAsRallyUser, vcs_ident: #{vcs_ident}, rally: #{rally}, logger: #{logger}, config: #{config}"
##
        if rally.nil?
            problem = "EmailAddressAsRallyUser not provided a RallyVCSConnection instance to use"
            boomex = VCSEIF_Exceptions::UnrecoverableException.new(problem)
            raise boomex, problem
        end
        if rally.class.name !~ /RallyVCSConnection/
            problem = "rally argument for EmailAddressAsRallyUser is not a RallyVCSConnection instance - #{rally.class}"
            boomex = VCSEIF_Exceptions::UnrecoverableException.new(problem)
            raise boomex, problem
        end
        @rally = rally

        @log = nil
        @log = logger if not logger.nil?

        @user_cache = rally.getRallyUsers() # will be keyed by email address of a valid Rally user (aka UserName)
        if @log and @log.respond_to?('debug')
            @log.debug('EmailAddressAsRallyUser user cache populated with %d entries' % @user_cache.length)
        end
    end


    def extractEmailAddress(committer)
        %{
            Attempt to extract the email address in the committer string.
            If the  attempt fails, return nil.
            If the email address is a valid Rally Username, return the email address.
            Otherwise return nil.
         } 
        if @log and @log.respond_to?('debug')
            @log.debug("EmailAddressAsRallyUser.extractEmailAddress called with committer parm: |%s|" % committer)
        end
##
##    puts " in EmailAddressAsRallyUser.extractEmailAddress for |#{committer}|"
##
        if committer.count(' ') == 0 and committer =~ /^#{EMAIL_ADDRESS_PATTERN}$/
            result = nil
            result = committer if @user_cache.include?(committer)
            if @log and @log.respond_to?('debug')
                blurb = "EmailAddressAsRallyUser.extractEmailAddress committer -> email_address: |%s| via %s"
                @log.debug(blurb % [result, 'EMAIL_ADDRESS_PATTERN'])
                @log.debug('EmailAddressAsRallyUser for "%s"  found Rally UserName: "%s"' % [committer, result])
            end
            return result
        end

        email_address = nil
        md = COMPOUND_IDENT_PATTERN.match(committer)
        if not md.nil?
            email_address = md[:email_addr]
            if @log and @log.respond_to?('debug')
                blurb = "EmailAddressAsRallyUser.extractEmailAddress committer -> email_address: |%s| via %s"
                @log.debug(blurb % [email_address, 'COMPOUND_IDENT_PATTERN'])
            end
        else
            md = ALT_COMPOUND_IDENT_PATTERN.match(committer)
            if not md.nil?
                email_address = md[:email_addr]
                if @log and @log.respond_to?('debug')
                    blurb = "EmailAddressAsRallyUser.extractEmailAddress committer -> email_address: |%s| via %s"
                    @log.debug(blurb % [email_address, 'ALT_COMPOUND_IDENT_PATTERN'])
                end
            end
        end
##
##  puts "email_address: |#{email_address}|"
##
        result = nil
        result = email_address if @user_cache.include?(email_address)
        if @log and @log.respond_to?('debug')
            @log.debug('EmailAddressAsRallyUser for "%s"  found Rally UserName: "%s"' % [committer, result])
        end
        return result
    end


    def service(target)
        return extractEmailAddress(target)
    end

end
