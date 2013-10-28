# Copyright 2001-2013 Rally Software Development Corp. All Rights Reserved.

class MetricsPoster
    def initialize()
        x = 'z'
    end

    def service(changesets)
        puts "MetricsPoster.service called to post info about %d recently added Changesets in Rally" % changesets.length
    end
end
