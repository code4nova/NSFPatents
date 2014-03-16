#!/usr/bin/env ruby

## USAGE:
##   test.rb {filename|action} ...
## WHERE:
##   filename   = "ipg140311.zip" or similar (anything which isn't a known action)
##   action     = one of "download", "extract"

require 'pathname'
require 'net/http'

##
## Helper methods
##

def get_full_year(filename)
  partial_year = /^...(\d\d)\d\d\d\d\.zip$/.match(filename)[1]
  full_year = (partial_year.to_i < 50 ? "20" : "19") + partial_year
end

def extract_download_params(filename)
  download_server = "patents.reedtech.com"

  if filename =~ /^ipa\d{6}.zip$/  # application
    full_year = get_full_year filename
    server_path = "/downloads/ApplicationFullText/#{full_year}/#{filename}"
  elsif filename =~ /^ipg\d{6}.zip/ # grant
    full_year = get_full_year filename
    server_path = "/downloads/GrantRedBookText/#{full_year}/#{filename}"
  else
    raise "unknown file type (#{filename})"
  end

  return download_server, server_path
end

def download_file(server, path, local_filename=nil)
  local_filename ||= Pathname.new(path).basename

  Net::HTTP.start server do |http|
    open(local_filename, "wb") do |file|
      http.request_get path do |response|
        response.read_body do |segment|
          file.write segment
        end
      end
    end
  end
end

def line_contains_nsf(line)
  /\bN\W*S\W*F\b|National Science Foundation/.match(line)
end

def extract_file(xml_filename, extract_filename)
  File.open(extract_filename, "w") do |fout|
    ## write some boilerplates
    fout << %q{<?xml version="1.0" encoding="UTF-8"?>} << "\n"
    fout << %q{<!DOCTYPE us-patent-application SYSTEM "us-patent-application-v43-2012-12-04.dtd" [ ]>} << "\n"
    fout << %q{<root>} << "\n"

    ## extract the relavent data
    File.open(xml_filename, "r") do |fin|
      line_iter = fin.each_line
      current_block_lines = []
      inside_block        = false
      block_contains_nsf  = false

      line_count  = 0
      block_count = 0

      begin
        current_line = line_iter.next

        line_count += 1
        puts "line #{line_count}" if line_count % 1e6 == 0

        if inside_block
          current_block_lines << current_line

          match_info = line_contains_nsf(current_line)
          if match_info
            block_contains_nsf = true
            puts "line #{line_count} in block #{block_count} contains NSF-related term (#{match_info})"
          end

          if current_line =~ %r{</us-patent-application>} # leaving the block
            #puts "line #{line_count}: leaving block"
            if block_contains_nsf
              #puts "block #{block_count} contains NSF-related term"
              current_block_lines.each{|line| fout.write line}
            end
            current_block_lines = []
            inside_block = false
          end
        elsif current_line =~ %r{<us-patent-application .*>} # entering a block
          #puts "line #{line_count}: entering block"
          current_block_lines << current_line

          inside_block        = true
          block_count        += 1
          block_contains_nsf  = false
        end
      end while !fin.eof?
    end

    ## write some more boilerplates
    fout << %q{</root>} << "\n"
  end
end

##
## Parse command-line arguments
##

actions   = ARGV.select{|s| s =~ /^download|unzip|extract|cleanup$/}
filenames = ARGV - actions
filenames = filenames.map{|f| f.gsub(/\..*$/, "")}

should_download = actions.empty? || (actions.include? "download")
should_unzip    = actions.empty? || (actions.include? "unzip")
should_extract  = actions.empty? || (actions.include? "extract")
should_cleanup  = actions.empty? || (actions.include? "cleanup")

puts "actions   = #{actions}"
puts "filenames = #{filenames}"

##
## Main Loop
##

filenames.each do |filename|
  puts "begin processing #{filename}"

  begin

    zip_filename      = "#{filename}.zip"
    xml_filename      = "#{filename}.xml"
    extract_filename  = "#{filename}.extract"

    if should_download
      puts "  downloading #{filename}"

      download_server, server_path = extract_download_params zip_filename
      download_file download_server, server_path
    end

    if should_unzip
      puts "  unzipping #{filename}"

      raise "#{zip_filename} doesn't exist" unless File.exists? zip_filename
      system("unzip -o -p #{zip_filename} > #{xml_filename}")
    end

    if should_extract
      puts "  extracting #{filename}"

      raise "#{xml_filename} doesn't exist" unless File.exists? xml_filename
      extract_file xml_filename, extract_filename
    end

    if should_cleanup
      puts "  cleaning up #{filename}"

      File.delete zip_filename
      File.delete xml_filename
      File.delete extract_filename
    end

  rescue StandardError => e
    puts "=== ERROR (#{filename}) ==="
    puts e.message
    puts e.backtrace.inspect
  end

  puts "end processing #{filename}"
end



