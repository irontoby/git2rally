# Copyright 2001-2013 Rally Software Development Corp. All Rights Reserved.

require_relative "ralkup"  # for RallyUserNameLookup
require_relative "filemap" # for FileBasedUserNameLookup

class UserLookupChainGang

    attr_reader :config, :log, :vcs_ident

    def initialize(kwarg)
        """
        """
        vcs_ident  = kwarg['vcs_ident'] || 'Mercurial'
        rally      = kwarg['rally']     || nil
        logger     = kwarg['logger']    || nil
        config     = kwarg['config']    || 'MiddleName,user_map.txt'

        internalizeConfig(config)

        rallyLookup = RallyUserNameLookup.new('vcs_ident' => vcs_ident,
                                              'rally'     => rally, 
                                              'config'    => @config['rally'], 
                                              'logger'    => logger)
##
##    puts "UserLookupChainGang obtained a RallyUserNameLookup instance..."
##    puts "rallyLookup instance has these methods: |#{rallyLookup.public_methods}|"
##    puts "rallyLookup instance has these instance vars: |#{rallyLookup.instance_variables}|"
##

        fileLookup  = FileBasedUserNameLookup.new('vcs_ident' => vcs_ident,
                                                  'config'    => @config['file'], 
                                                  'logger'    => logger)
##
##    puts "UserLookupChainGang obtained a FileBasedUserNameLookup instance..."
##
        @lookup_sequence = [rallyLookup, fileLookup]
    end


    private
    def internalizeConfig(config)
        """
            Figure out a better way to have a single arg carry multiple pieces of config
            info for various instruments.
            Maybe one way is to just name a file with whatever you want in it.
            For now, maybe we assume a separator char of '|'
        """
        #elements = config.split('|')

        @config = { 'rally' => 'FirstName,LastName',
                    'file'  => 'user_map.txt,:'
                  }
    end

    public
    def service(target)
        for agent in @lookup_sequence do
            result = agent.send('service', target)
            return result if !result.nil?
        end
        return nil
    end

end
