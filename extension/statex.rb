# Copyright 2001-2013 Rally Software Development Corp. All Rights Reserved.

#####################################################################################################
#
# statex.rb -- VCS commit message action and artifact extractor Class hierarchy/mechanism
#             and test script to demonstrate how to extract segments of a commit message
#             that contain artifact ident(s) and action(s)
#
#    Assume that any artifact ident and action verbiage must occur before any other verbiage
#    and that we will _not_ operate on any such likely patterns if they are interrupted by
#    non artifact ident / action text.
#    ie., DE1235 Fixed and wovnerio never tested this  <-- qualifies
#    Completed TA19 TA12 Fixed DE321 deprecated old rounding operation <-- qualifies
#    updated US123 feature by delegating to proxy as demo in S344 <-- qualifies for artifacts only
#    the rogoshus project won't like that I Rejected DE123  <-- qualifies for artifacts only
#    unable to figure out if DS3423 is ever validated <--- does not qualify
#    A message that only mentions artifacts and not any valid action also qualifies
#     it just won't result in the update of the artifact State/ScheduleState attribute
#   
#    Collapse all whitespace (space, tab, newline) sequences into a single space
#    then split the message on whitespace, and reverse the order to obtain a stack of words.  
#    pop words off the stack until a word
#       doesn't match the ACTION_WORD_PATTERN or ARTIFACT_IDENT_PATTERN
#    have a Hash of {action => [artifacts]} as the result
#    if you get the artifacts first, then you have to hold on to them until you get the action
#
#####################################################################################################

#####################################################################################################

ACTION_WORD_PATTERN    = Regexp.compile('[A-Z][a-z]+[a-zA-Z_-]+')
ARTIFACT_IDENT_PATTERN = Regexp.compile('(?<art_prefix>[A-Z]{1,2})(?<art_num>\d+)')

# Example of regex to detect a valid artifact FormattedID value and list of valid action words
VALID_ARTIFACT_ABBREV  = Regexp.compile('^DE|S|US|TA|TC$')
VALID_ACTION_WORDS = ['Open', 'Closed', 'Fixed', 'Completed', 'Implemented']
#VALID_ACTION_WORDS = ['Open', 'Closed', 'Fixed', 'Completed', 'Implemented', 'Replicated', 'Vindicated']

#####################################################################################################

class ActionsAndArtifactsExtractor
    def initialize(artifact_specs)
        """
            artifact_specs is a list of Hashes with each Hash having the following info:
                abbrev :  S | US | DS | DE | TA | TC etc..
                update_field:  State | ScheduleState | CustomField etc...
                valid_values:  Submitted, Open, Defined, Fixed, Closed, Replicated, Rejected, etc.
        """
        @artifact_specs = artifact_specs
        abbrevs = artifact_specs.collect {|afs| afs['abbrev']}
        artifact_abbrev_pattern = '^%s$' % abbrevs.join("|")
        @valid_artifact_abbrev = Regexp.compile(artifact_abbrev_pattern)

        @valid_action_words = []
        @artifact_specs.each {|afs| @valid_action_words.concat(afs['valid_values'])}
    end

    def extractActionGroups( message)
        """
            Your subclass will need to implement this method to return a Hash
            with actions and artifact targets extracted from the message.
        """
        raise NotImplementedError
    end

    def service(message)
        extractActionGroups(message)
    end

end

#####################################################################################################

class BasicActionsAndArtifactsExtractor < ActionsAndArtifactsExtractor

    def extractActionGroups(message)
        """
            Given a string (possibly multiline...) with a commit message that may contain
            references to Rally artifacts and intended state related update values, 
            extract those references and values.
            Return a Hash keyed by update value with the list of Rally artifacts 
            to be updated with that update value for each update value.
            Example:
               {nil => ['S123', 'DE432'], 'Completed' => ['TA12', 'TA18', 'S33']}
        """

        msg_stack = message.split()
        msg_stack.reverse!

        actgrp = nil
        action_groups = []

        while msg_stack.length > 0
            word = msg_stack.pop()
##
##            puts "word: |#{word}|"
##

            action_word   =    ACTION_WORD_PATTERN.match(word)
            artifact_word = ARTIFACT_IDENT_PATTERN.match(word) 

            if not action_word and not artifact_word
                next
            end

            if not actgrp
                actgrp = ActionGrouping.new()
            end

            if action_word
##
##                puts "  action: %s" % word
##
                if actgrp.populated?('action')
##
##                    puts "actgrp full: %s" % actgrp.to_s
##
                    action_groups.push(actgrp)
                    actgrp = ActionGrouping.new()
                end

                if not @valid_action_words.include?(word)
                    word = nil
                end
                actgrp.setAction(word)
            end

            if artifact_word
                art_prefix = artifact_word[:art_prefix]
                if @valid_artifact_abbrev.match(art_prefix)
##
##                    puts "  artifact: %s" % word
##
                    if actgrp.populated?('target')
##
##                        puts "actgrp full: %s" % actgrp.to_s
##
                        action_groups.push(actgrp)
                        actgrp = ActionGrouping.new()
                    end
                    actgrp.addTarget(word)

                else
                    break
                end
            end
        end

        action_groups.push(actgrp) if actgrp and actgrp.complete?

##
##        puts "There are %d action_groups" % action_groups.length
##
        groups = coalesceActionGroups(action_groups)
        # now create our action_groups Hash to return to caller
        action_groups = {}
        groups.each do |ag|   #ag --> ActionGrouping instance
            action_groups[ag.action] = ag.targets if ag.targets
        end
            
        return action_groups
    end


    private
    def coalesceActionGroups(action_groups)
        """
            given a list of ActionGrouping instances, produce a list of ActionGroups 
            in which each action is unique. 
            Multiple instances of an ActionGroup with the same action contribute
            their targets to the single resultant holder of the action.
        """
        min_list = []
        action_groups.each do |ag|  # ag --> ActionGrouping instance 
##
##            puts "ag: #{ag.to_s},   action = |#{ag.action}|  targets = |#{ag.targets}|"
##
            uniq = min_list.select {|u| u.action == ag.action}
##
##            puts " uniq: |#{uniq}|"
##
            if not uniq or uniq.length == 0
                min_list.push(ag)
            else
                uniq = uniq.pop()
                uniq.targets.concat(ag.targets)
            end
        end

        return min_list
    end

end

#####################################################################################################

class ActionGrouping

    attr_reader :action, :targets

    def initialize()
        @action     = nil
        @targets    = []
        @first_item = nil
    end

    def setAction(action)
        @action = action
        @first_item = 'action' if not @first_item
        #puts "set action to %s , first_item? %s" % (action, true if @first_item == 'action' else false)
    end
        
    def addTarget(target)
        @targets.push(target)
        @first_item = 'target' if not @first_item
    end

    def populated?(intent='action')
        return false if not @targets
        return false if not @action

        return true if intent == 'action'
        return true if intent == 'target' and @first_item == 'target'

        return false
    end

    def complete?()
        return true if @targets.length > 0
    end

    def to_s()
        action = @action
        if @action
            action = "'%s'" % @action
        end
        return "#{action} -NO TARGETS-" if @targets.length == 0
        return "%s: %s" % [action, @targets.join(', ')]
    end
end

#####################################################################################################

TEST_ITEMS = \
    [ 
      ['Completed the work of 12 people in 1 hour',                     # non-conforming
       {} ],

      ['STP9321 this is not a reference to a Completed DE15 artifact',  # non-conforming
       {} ], 

      ['USB-2  not a valid artifact reference',                         # non-conforming
       {} ], 

      ['S123 Completed',                                                # conforming
       {'Completed' => ['S123']} ], 

      ['DE103 when will this ever be fixed?',                           # conforming
       {nil => ['DE103']} ], 

      ['DE123 Fixed and you can bank on it',                            # conforming
       {'Fixed' =>  ['DE123']} ], 

      ['S123 Completed Fixed TA123 S123',                               # conforming (but non-std))
       {'Completed' => ['S123'], 'Fixed' => ['TA123', 'S123']} ], 

      ['S1234 S3421 a wo0ookies work is never done...',                 # conforming
       {nil => ['S1234', 'S3421']} ], 

      ['TA123 TA345 Fixodent with molars behind',                       # conforming
       {nil => ['TA123', 'TA345']} ], 

      ['Fixed DE1054 4324 lower case chaos KG324',                      # conforming
       {'Fixed' => ['DE1054']} ], 

      ['Completed S3245',                                               # conforming
       {'Completed' => ['S3245']} ], 

      ['Replicated DE123 DE832',                                        # conforming
       {'Replicated' => ['DE123', 'DE832']} ], 

      ['Fixed DE532 Completed S342 for your peace of mind',             # conforming
       {'Fixed' => ['DE532'], 'Completed' => ['S342']} ], 

      ['Replicated DE123 DE832 Defiled S174',                           # conforming
       {nil => ['S174'], 'Replicated' => ['DE123', 'DE832']} ], 

      ['Replicated DE234 DE329 Barfek S324 S432',                       # conforming
       {'Replicated' => ['DE234', 'DE329'], nil => ['S324', 'S432']} ], 

      ['Completed S432 Fixed DE549 Completed TA617 now go home',        # conforming
       {'Completed' => ['S432', 'TA617'], 'Fixed' => ['DE549']} ],

      ['DE543 Completed DE322 Fixed S235 Completed overnight delivery', # conforming
       {'Completed' => ['DE543', 'S235'], 'Fixed' => ['DE322']} ], 

    ] 

B_TEST_ITEMS = \
    [ 
      ['DE103 when will this ever be fixed?',                           # conforming
       {nil => ['DE103']} ], 

     # ['Completed the work of 12 people in 1 hour',                     # non-conforming
     #  {} ],

     # ['STP9321 this is not a reference to a Completed DE15 artifact',  # non-conforming
     #  {} ], 

    ] 

#####################################################################################################

def test()

    artifact_specs = [ {'abbrev'       => 'S' , 
                        'update_field' => 'ScheduleState', 
                        'valid_values' => ['Defined', 'InProgress', 'Implemented', 'Completed']
                       }, 

                       {'abbrev'       => 'DE', 
                        'update_field' => 'State',         
                        'valid_values' => ['Open', 'Fixed', 'Closed']
                       }, 

                       {'abbrev'       => 'TA', 
                        'update_field' => 'State',         
                        'valid_values' => ['Completed', 'Vindicated']
                       }, 

                       {'abbrev'       => 'TC', 
                        'update_field' => 'State',         
                        'valid_values' => ['Replicated']
                       }
                     ]

    TEST_ITEMS.each_with_index do |pair, zbix|
        ix = zbix+1
        message, expected = pair
        puts "%2d: %s" % [ix, message]
        puts "    expected ->   %s" % expected.to_s
        extractor = BasicActionsAndArtifactsExtractor.new(artifact_specs)
        action_targets = extractor.extractActionGroups(message)
        conforming = 'non-conforming'
        conforming =     'conforming' if action_targets.length > 0
        puts "    %s    %s" % [conforming, "#{action_targets}"]
        #puts ""
    end
end

#####################################################################################################
#####################################################################################################

#test()

