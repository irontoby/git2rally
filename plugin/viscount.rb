# Copyright 2001-2013 Rally Software Development Corp. All Rights Reserved.

##################################################################################################
#
# facility containing a helper class for VCS connector plugins to normalize 
#  VCS system committer values.
#
##################################################################################################

##################################################################################################

#for entries that look like |Name Surname <whomever@somewhere.org>|
VCS_COMPOUND_IDENT_PATTERN     = Regexp.compile("^\s*(?<ident>[^<]+)\s+<(?<email_addr>[^@]+@.+)>\s*$")
# for entries that look like |Name Surname whomever@somewhere.org|
VCS_ALT_COMPOUND_IDENT_PATTERN = Regexp.compile("^\s*(?<ident>.+)\s+(?<email_addr>[^@]+@[^ ]+)\s*$")


##################################################################################################

class ViscountIdentifritz
    """
        
    """
    def initialize(vcs_ident='Mercurial')
        """
            Instantiator must provide a string for the vcs_ident keyword that identifies the
            VCS system from which the candidate committer value originated from.

            In some cases the VCS system provides a committer string that is compound, ie.,
            it has both a committer identifier and a committer email address, while other VCS
            systems provide only a committer identifier as a single value.
        """
        vcs_ident_facility = { 'svn'        => method('svn_identifier'),
                               'subversion' => method('svn_identifier'),
                               'git'        => method('git_identifier'),
                               'perforce'   => method('perforce_identifier'),
                               'p4'         => method('perforce_identifier'),
                               'tfs'        => method('tfs_identifier'),
                               'mercurial'  => method('mercurial_identifier'),
                               'hg'         => method('mercurial_identifier'),
                               'bazaar'     => method('bazaar_identifier'),
                               'bzr'        => method('bazaar_identifier'),
                               'clearcase'  => method('clearcase_identifier'),
                               'cc'         => method('clearcase_identifier'),
                             }
        begin
            @garglespit = vcs_ident_facility[vcs_ident.downcase()]
        rescue Exception => ex
            raise Exception.new('ERROR: Supplied vcs_ident: %s not recognized, Contact Technical Support' % vcs_ident)
        end
    end


    def normalize(committer) return @garglespit.call(committer).strip() end
    def identify(committer)  return @garglespit.call(committer).strip() end
        
    def single_value_identifier(committer)
        """
            A single value identifier is the most simple case, 
            merely strip any surrounding whitespace from the committer and return the result.
        """
        return committer.strip()
    end

    def ident_email_identifier(committer)
        %{
            An ident / email identifier is one where the committer value is "compound" in the 
            sense that there are two pieces of information stuffed into a single string.
            Typically, this takes the form of: "First Last" <biglots@lotsobig.com>  or
                                                First Last <biglots@toobig.com>
             where the compound components are the actual identifier and the committers email address.
         } 
        # look for a 'JoeBob Nelson <jobobn@scruvy.com>'   type of committer value
        #       or a ' Roscoe Bovine rsocob@barnyard.com'  type of committer value
        #       or a '"Niven Frooble" nivdude@plinkus.com' type of committer value
        md = VCS_COMPOUND_IDENT_PATTERN.match(committer)
        if not md.nil?
            return md[:ident].gsub('"', '').strip()
        end

        # look for a degenerate 'Bismutch Kolndytz bisdytz@dumplings.com' type of committer value
        md = VCS_ALT_COMPOUND_IDENT_PATTERN.match(committer)
        if not md.nil?
            result = md[:ident].gsub('"', '').strip()
            return result
        end

        compound = committer.strip()
        if compound.count(' ') == 1
            left, right = compound.split(" ", 2)
            return left.gsub('"', '').strip()
        end

        return committer  # give up, return supplied value intact
    end
  
    def svn_identifier       (committer) return single_value_identifier(committer) end
    def perforce_identifier  (committer) return single_value_identifier(committer) end
    def tfs_identifier       (committer) return single_value_identifier(committer) end
    def clearcase_identifier (committer) return single_value_identifier(committer) end
    def mercurial_identifier (committer) return  ident_email_identifier(committer) end
    def git_identifier       (committer) return  ident_email_identifier(committer) end
    def github_identifier    (committer) return  ident_email_identifier(committer) end
    def bazaar_identifier    (committer) return  ident_email_identifier(committer) end
 
end
