#!/usr/bin/env ruby

require 'csv'

csv = CSV.parse(File.read(ARGV[0]), headers: true)
column_widths = csv.to_a.inject(Array.new(csv.headers.size, 0)) do |result, row|
  row.each_with_index do |elem,idx|
    elem ||= ""
    if (elem && elem.size > result[idx])
      result[idx] = elem.size
    end
  end
  result
end

format = "%" + column_widths.collect{|cw| "#{cw}s"}.join(", %")

csv.to_a.each do |row|
  puts format % row
end
