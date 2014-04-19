#!/usr/bin/env ruby

require 'csv'

def parse_csv(filename)
  CSV.parse(File.read(filename), headers: true)
end

unless ARGV.size > 0
  puts "no CSV filenames given"
  exit
end

combined_csv = ARGV.inject(parse_csv(ARGV.shift)) do |combined_csv, filename|
  parse_csv(filename).each do |row|
    combined_csv << row
  end
  combined_csv
end

puts combined_csv
