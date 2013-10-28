#!/usr/bin/env ruby
# Copyright 2001-2013 Rally Software Development Corp. All Rights Reserved.

# For local development testing
# ruby .\lib\vcs2rally.rb tfs_sample.yml
# $: << File.expand_path(File.join(File.dirname(__FILE__), '../lib'))
# $: << File.expand_path(File.join(File.dirname(__FILE__), '..'))
# require 'vcs_conn/tfs_connection'

##########################################################################################
#
# git2rally  -- create changeset/change info in Rally from Git commits
#
USAGE = %{
Usage: ruby git2rally.rb <config_file.yml> 
 
       where the config file named must have content in YAML format with 5 sections;
         the first must be a single entry naming the Connection, in this case a VCSConnector
         followed by a section for the connection to the Rally system, 
         a section for the connection to the Git system, one
         for the Services configuration and one for any Transforms
    
       An invocation of git2rally.rb results in a "single-shot" scan and operation.
       To effect this on an ongoing basis, use cron or Windows Task Scheduler.
}
##########################################################################################

if RUBY_VERSION < "1.9.2"
   $stderr.write(
    "ERROR, outdated version of Ruby: #{RUBY_VERSION}.\n" +
    "Upgrade to Ruby 1.9.2 or better.\n"
   )
end

require "vcseif"

def main(args)
    if args.length == 1 and args.first == '--version'
       puts VCSEIF::Version
       exit(0)
    end

    if args.length < 1
      problem = "Insufficient command line args, must be at least a config file name\n"
      $stderr.write(problem)
      exit(1)
    end

    base_script_name = File.basename(__FILE__, File.extname(__FILE__))
    driver = VCSConnectorDriver.new(base_script_name)
    ret_code = driver.execute(args)
    exit(ret_code)
end

main(ARGV)