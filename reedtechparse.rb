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
timecounter = Time.now
todaysdate = Date.new(Time.now.year,Time.now.month,Time.now.day)
datelooperapps = Date.new(2002,10,10)
# Set datelooper to whatever date you want to start parsing the bulk files from.
datelooper = Date.new(2002,10,10)
datelooperissued = datelooperapps - 2
# Set testdate to whatever date you want to stop parsing the bulk files from
testdate = Date.new(2003,6,1)

# Pull in one weeks worth of patent apps and issued patents
# Comment out the loop code for now to just do proof of concept
  while datelooper < testdate
    if datelooper.year < 2005
      prefix = ""
    else
      prefix = "i"
    end
    monthstrapp = datelooperapps.month.to_s
    if datelooperapps.month < 10
      monthstrapp = "0" + datelooperapps.month.to_s 
    end
    monthstrpat = datelooperissued.month.to_s
    if datelooperissued.month < 10
      monthstrpat = "0" + datelooperissued.month.to_s
    end
      daystrapp = datelooperapps.day.to_s
    if datelooperapps.day < 10
      daystrapp = "0" + datelooperapps.day.to_s
    end
    daystrpat = datelooperissued.day.to_s
    if datelooperissued.day < 10
      daystrpat = "0" + datelooperissued.day.to_s
    end
    patentappfile = prefix + "pa" + (datelooper.year).to_s[2..3] + monthstrapp + daystrapp + ".zip"
    patentissuefile = prefix + "pg" + (datelooper.year).to_s[2..3] + monthstrpat + daystrpat + ".zip"
    
    Net::HTTP.start("patents.reedtech.com") do |http|
      begin
        
        file = open(patentappfile, 'wb')
        http.request_get("/downloads/ApplicationFullText/" + datelooper.year.to_s + "/" + prefix + "pa" + (datelooper.year).to_s[2..3] + monthstrapp + daystrapp + ".zip") do |response|
          response.read_body do |segment|
            file.write(segment)
          end
        end
      ensure
        file.close
      end
    end
    
    Net::HTTP.start("patents.reedtech.com") do |http|
      begin
        file = open(patentissuefile, 'wb')
        http.request_get("/downloads/GrantRedBookText/" + datelooper.year.to_s + "/" + prefix + "pg" + (datelooper.year).to_s[2..3] + monthstrpat + daystrpat + ".zip") do |response|
          response.read_body do |segment|
            file.write(segment)
          end
        end
      ensure
        file.close
      end
    end
    
    # Then unzip them
    system("unzip -o #{patentappfile}")
    system("unzip -o #{patentissuefile}")
    # Clean up
    File.delete(patentappfile)
    File.delete(patentissuefile)
    i = -1
    j = -1
   currdoc = Array.new
   currdocpats = Array.new
    # Use ruby to split the concatenated XML files into separate docs, each doc going into an array cell
    f = File.open( patentappfile[0..-4] + "xml")
    f.each do |line|
      data = line
      if data.include? "<?xml version="
        i = i + 1
        currdoc[i] = data.to_s
      else
        currdoc[i] = currdoc[i] + data.to_s
      end
    end
    f = File.open( patentissuefile[0..-4] + "xml")
    f.each do |line|
      data = line
      if data.include? "<?xml version="
        j = j + 1
        currdocpats[j] = data.to_s
      else
        currdocpats[j] = currdocpats[j] + data.to_s
      end
    end
  
  
  # In our Xpath query, we want to find where the federal research statement says "National Science Foundation" or says "NSF"
  currdoc.each do |appdoc|
    xmldoc = Nokogiri::XML(appdoc)
    xmldoc.xpath("//patent-application-publication//*[contains(federal-research-statement,'National Science Foundation') or contains(federal-research-statement,'NSF')]/..").each do |app|
        xmlfile = File.open(datelooperapps.to_s + "applications.xml", 'a+')
          xmlfile.puts appdoc
        xmlfile.close
    end
  end  
# The below is for future work on getting the specific customer required fields from the relevant XML docs
=begin
          # Now we have a nodeSet (array) of parents- so we want to get the meta data requested by the customer for this application
          # Iterate through the nodeSet and get out all the meta data for each app
          # form the CSV line
          # Application Number (or Patent Number), Governmnet Interent, Abstract, Inventors, Applicant, Assignee, Family ID, Filed, PCT Filed, PCT No, 371 Date, Prior Pub Data,
          # Document Identifier, Publication Date, Related Patent Documents, Issue Date (if patent), US Patent citations
          #csvline = "APN, GOVT, ABST, IN, AANM, AN, FMID, APD, PTAD, PT3D, PPPD, KD, PD, RLAP, USCITATIONS"
          #nufile = File.open(datelooperapps.to_s + ".csv", 'a+')
          #  nufile.puts csvline
          #nufile.close
          #csvline = ""
          apn = app.xpath("//application-number/doc-number/text()")
          govt = app.xpath("//federal-research-statement/text()").to_s
          abst = app.xpath("//subdoc-abstract//text()").to_s
          inventor = app.xpath("//inventors/text()").to_s
          aanm = "unknown"
          an = "unknown"
          fmid = "unknown"
          apd = app.xpath("//filing-date/text()").to_s
          ptad = "unknown"
          pt3d = "unknown"
          pppd = "unknown"
          kd = app.xpath("//kind-code/text()").to_s
          pd = app.xpath("//document-date/text()").to_s
          rlap = "unknown"
          uscitations = "unknown"
          csvline = csvline + apn[0] + "," +
          govt + "," +
          abst + "," +
          inventor + "," +
          aanm + "," +
          an + "," + fmid + "," +
          apd + "," +
          ptad + "," + pt3d + "," +
          pppd + "," +
          kd + "," +
          pd + "," +
          rlap + "," + uscitations
          # write out CSV line into file
          nufile = File.open(datelooperapps.to_s + ".csv", 'a+')
            nufile.puts csvline
          nufile.close
=end
# Now search through the patent XML stored in the currdocpats array   
  currdocpats.each do |appdoc|
    xmldoc = Nokogiri::XML(appdoc)
    xmldoc.xpath("//PATDOC//*[contains(GOVINT,'National Science Foundation') or contains(GOVINT,'NSF')]/..").each do |app|
        xmlfile = File.open(datelooperissued.to_s + "patents.xml", 'a+')
          xmlfile.puts appdoc
        xmlfile.close
    end
  end
  # advance to the next week
  datelooper = datelooper + 7
  datelooperissued = datelooperissued + 7
  datelooperapps = datelooperapps + 7
end # end while
puts "Time to complete: " + (Time.now - timecounter).to_s