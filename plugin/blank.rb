# Copyright 2001-2013 Rally Software Development Corp. All Rights Reserved.

##################################################################################################
#
# Plugin module for VCS connector to perform user name extraction.
#  Contains a class with api elements to allow Author transformation type calls,
#  although all this class does is accept the call and return back an empty string
#
##################################################################################################

class Blank
    """
        Just provide the basic Author transformation API elements to be able to 
        pass back an empty string (blank).
    """

    def initialize(kwarg)
        """
            Instantiator must provide a string for the vcs_ident keyword that identifies the
            VCS system from which the candidate committer value originated from.
            In some cases the VCS system provides a committer string that is compound, ie.,
            it has both a committer identifier and a committer email address, while other VCS
            systems provide only a committer identifier as a single value.
            A logger argument can also be provided, which for the purposes of this implementation
            does absolutely nothing.
            A config argument can also be provied, but like any logger argument, the presence or
            absence has no effect.
        """
        #vcs_ident = kwarg['vcs_ident'] || nil
        #logger    = kwarg['logger']    || nil
        config    = kwarg['config']    || nil
    end


    def service(target)
        return ""
    end

end
