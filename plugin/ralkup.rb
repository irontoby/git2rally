# Copyright 2001-2013 Rally Software Development Corp. All Rights Reserved.

##################################################################################################
#
# Plugin module for VCS connector to perform user name mappings.
#  Contains a class with logic to perform Rally user lookups given some identifier
#
##################################################################################################

require "rally_api"  # for RallyAPI::RallyQuery

require "vcseif/utils/exceptions"
require_relative "viscount"  # for ViscountIdentifritz

##################################################################################################

class RallyUserNameLookup
    %{
        An instance of this class implements a plugin to provide Rally user lookup behavior.  

        The VCS connector obtains an instance of this class at connector initialization time,
        providing arguments of a config string that identifies the fields in a Rally User entity
        that will be used to construct match targets for VCS committer strings, a "connected" 
        RallyVCSConnection instance, a list of attributes
        in a Rally User item to use for the lookup, a format string to assemble the Rally User
        attributes into the specific value to be matched.
     } 

    attr_reader :user_cache

    def initialize(kwarg)
        """
            Instantiator must provide a string for the vcs_ident keyword that identifies the
            VCS system from which the candidate committer value originated from.
            In some cases the VCS system provides a committer string that is compound, ie.,
            it has both a committer identifier and a committer email address, while other VCS
            systems provide only a committer identifier as a single value.
            Instantiator must provide a string containing one or more Rally User entity attribute
            names that will be assembled to provide match targets for each lookup attempt,
            a list of Rally User attributes, and if they do, they should also provide a format argument
            A logger argument can also be provided, which for the purposes of this implementation
            will result in DEBUG log messages being generated for this method and the lookup method.
        """
        vcs_ident = kwarg['vcs_ident'] || nil
        rally     = kwarg['rally']     || nil
        logger    = kwarg['logger']    || nil
        config    = kwarg['config']    || nil

        @user_cache = {}

        if rally.nil?
            problem = "RallyUserNameLookup not provided a RallyAPI::RallyRestJson instance to use"
            boomex = VCSEIF_Exceptions::UnrecoverableException.new(problem)
            raise boomex, problem
        end
        if rally.class.name !~ /RallyVCSConnection/
            problem = "rally argument for RallyUserNameLookup initialization is not a RallyAPI::RallyRestJson instance"
            boomex = VCSEIF_Exceptions::UnrecoverableException.new(problem)
            raise boomex, problem
        end
        @rally = rally

        @ident_attributes = [config]
        if config.include?(' ')
            @ident_attributes = config.split().select {|token| token != ','}
        elsif config.include?(",")
            @ident_attributes = config.split(',').select {|token| token != ' '}
        end
        @log = nil
        @log = logger if logger
        validateAttributes()
        # @user_cache will be keyed by result of an assembly of @ident_attributes values
        populateUserCache()
        if @log
            @log.debug('RallyUserNameLookup user cache populated with %d entries' % @user_cache.length)
        end

        @fritzi = ViscountIdentifritz.new(vcs_ident)
    end


    def lookup(committer)
        """
            Attempt to match up the given identifier with a Rally User.
            If there is a match, the Rally User UserName attribute of the matched User item is
            returned.  Otherwise, a nil is returned.
        """
##
##        puts "RallyUserNameLookup.lookup called with committer parm: |%s|" % committer
##
        identifier = @fritzi.identify(committer)
##
##        puts "RallyUserNameLookup.lookup committer -> identifier: |%s|" % identifier
##
        result = @user_cache[identifier] || nil
        if @log
            @log.debug('RallyUserNameLookup for "%s"  found UserName: "%s"' % [committer, result])
        end
        return result
    end

    def service(target)
        return lookup(target)
    end


    private
    def validateAttributes()
        """
            The attributes named upon instantiation have to exist for a Rally User item.
            Additionally, for the purposes of lookup there are only certain attributes
            can be used to construct a matchable value.  These attributes are:
               Name
               DisplayName
               ShortDisplayName
               UserName
               FirstName
               MiddleName
               LastName
               EmailAddress
               OnpremLdapUsername 
        """
        valid_user_attributes = ['Name', 'DisplayName', 'ShortDisplayName', 'UserName',
                                 'FirstName', 'MiddleName', 'LastName', 'EmailAddress', 
                                 'OnpremLdapUsername',
                                ]
        bad_attrs = @ident_attributes.select {|attr| valid_user_attributes.include?(attr) != true}
        if not bad_attrs.empty?
            problem = "Invalid or inappropriate User attributes specified for lookup facility: %s"
            offenders = bad_attrs.join(", ")
            confex = VCSEIF_Exceptions::ConfigurationError.new(problem % offenders)
            raise confex, problem % offenders
        end
    end

    def populateUserCache()
        """
            Utilize the rally.getAllUsers(attributes) facility to obtain info on all Rally users and
            populate a cache keyed by the transform lookup target with the UserName as the 
            value for each key.  This makes it a snap to service the lookup method, we just
            have to raid the cache.
        """
        attributes = @ident_attributes.join(",")
        ruc = @rally.getRallyUsers(attributes)
        ruc.each_pair do |rally_user, urec|
            ident_attrs = @ident_attributes.collect {|attr_name| urec[attr_name] || ''}
            name = ident_attrs.select{ |attr_value| !attr_value.empty? }.join(" ").strip
            if name.length > 0 
                @user_cache[name] = urec['UserName']
                @log.debug("|%s| --> |%s|" % [name, urec['UserName']]) if @log
            end
        end
    end

end
