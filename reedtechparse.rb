#!/usr/bin/env ruby
require 'net/http'
require 'date'
require 'nokogiri'

# Download and parse through each Patent and Patent Application bulk file, looking in each one for where the Government Interest field says "NSF" or
# National Science Foundation
# From 2002-2004, the format of the URL for each bulk set (on a bi-weekly release basis) is:
# Patent Applications: http://patents.reedtech.com/downloads/ApplicationFullText/YYYY/paYYMMDD.zip
# -- For Example, Oct 3, 2002 is: http://patents.reedtech.com/downloads/ApplicationFullText/2002/pa021003.zip
# From then on, every week a new set is released. So, on each iteration, we will be doing "date math" adding 1 week to the
# Date until we reach the present date.
# From 2005-present, the format is http://patents.reedtech.com/downloads/ApplicationFullText/YYYY/ipaYYMMDD.zip
# -- For Example, Sept. 1, 2005 is: http://patents.reedtech.com/downloads/ApplicationFullText/2005/ipa050901.zip
# Issued Patents from 2002-2004: http://patents.reedtech.com/downloads/GrantRedBookText/YYYY/pgYYMMDD.zip
# -- For Example, Oct. 8, 2002 is: http://patents.reedtech.com/downloads/GrantRedBookText/2002/pg021008.zip
# Issued Patents from 2005-present is: http://patents.reedtech.com/downloads/GrantRedBookText/YYYY/ipgYYMMDD.zip
# -- For Example, Jan. 25, 2005 is: http://patents.reedtech.com/downloads/GrantRedBookText/2005/ipg050125.zip

# Initialize our date loop index to be the first dataset in FY 2003, so that
# date would have been: first thursday after October 1, 2002 which was October 3, 2002
# for patent apps, first file is October 3, 2002
# http://patents.reedtech.com/downloads/ApplicationFullText/2002/pa021003.zip
# For patent issued, first file is October 1, 2002
# http://patents.reedtech.com/downloads/GrantRedBookText/2002/pg021001.zip
todaysdate = Date.new(Time.now.year,Time.now.month,Time.now.day)
datelooperapps = Date.new(2002,10,3)
datelooperissued = datelooperapps - 2
Net::HTTP.start("http://patents.reedtech.com/") do |http|
  # Pull in one weeks worth of patent apps and issued patents
  while datelooper < todaysdate 
    patentapps = http.get("downloads/ApplicationFullText/" + yearlooper + "/" + datelooperapps + ".zip")
    issuedpatents = http.get("downloads/GrantRedBookText/" + yearlooper + "/" + datelooperissued + ".zip")
    # write the downloaded files locally
    open(patentapps + ".zip", "wb") do |file|
      file.write(resp.body)   
    end
    open(issuedpatents + ".zip", "wb") do |file|
      file.write(resp.body)   
    end
    # Then unzip them
    system("unzip -o #{patentapps}.zip")
    system("unzip -o #{issuedpatents}.zip")
    # Clean up
    File.delete(patentapps + ".zip")
    File.delete(issuedpatents + ".zip")
    puts "Done Importing & Unzipping!"
    # Now parse the XML (fun times)
    f = File.open(patentapps + ".xml")
    patentappsdoc = Nokogiri::XML(f)
    f.close
    f2 = File.open(issuedpatents + ".xml")
    patentappsdoc = Nokogiri::XML(f2)
    f2.close
    
  
  end #end the date loop
end # end the HTTP request
