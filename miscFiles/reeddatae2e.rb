#!/usr/bin/env ruby
#!/usr/bin/env ruby
require 'net/http'
require 'date'
require 'nokogiri'
require 'csv'

# Download and parse through each Patent and Patent Application bulk file, looking in each one for where the Government Interest field says "NSF" or
# National Science Foundation

#First Download the bulk XML file
timecounter = Time.now
#todaysdate = Date.new(Time.now.year,Time.now.month,Time.now.day)

# First command line arg is the bulk file to download
dlfile = ARGV[0]
# Second command line arg is "p" for patent or "a" for application
type = ARGV[1]
# Third command line arg is the year
fileyear = ARGV[2]
# Fourth Command is action - full, download, extract, or CSV
action = ARGV[3]



if type == "p"
  dlfilepath = "/downloads/GrantRedBookText/" + fileyear.to_s + "/" + dlfile.to_s
  writefileprefix = "NSFpatents"
else
  dlfilepath = "/downloads/ApplicationFullText/" + fileyear.to_s + "/" + dlfile.to_s
  writefileprefix = "NSFapplications"
end
if (action == "full" or action == "download")
  Net::HTTP.start("patents.reedtech.com") do |http|
    begin      
      file = open(dlfile, 'wb')
      http.request_get(dlfilepath) do |response|
        response.read_body do |segment|
          file.write(segment)
        end
      end
    ensure
      file.close
    end
  end
    
  # Then unzip them
  system("unzip -o #{dlfile}")
  # Clean up the zipfiles
  File.delete(dlfile)
end

# XML file downloaded. Now separate out the NSF XML docs
if (action == "full" or action == "extract")
  puts "Separating out the XML docs from the one large file"
  flag = false
  currdoc = ""
  f = File.open(dlfile[0..-4] + "xml")
  fsize = f.size
  xmlfile = File.open(dlfile[3..-4] + writefileprefix + ".xml", 'a+')
  iter = 0
  f.read(fsize).lines do |data|
    if (data.include? "<?xml version=" or data.include? "<!DOCTYPE ")
      if (iter < 2)
      # Write out the first two XML declarations, and put a root in after the second
        xmlfile.puts data.to_s
        if (iter == 1)
          xmlfile.puts "<root>"
        end
        iter = iter + 1
        next
      end
      if flag
        flag = false
        xmlfile.puts currdoc
      end
      currdoc = ""
      # Dont write in any of the other XML doc declarations
      next
    elsif (data.include? " NSF " or data.include? "National Science Foundation" or
            data.include? " NSF" or data.include? "NSF ")
      puts "While splitting the XML docs, found an NSF mentioning doc"
      currdoc = currdoc + data.to_s
      flag = true
    else
      currdoc = currdoc + data.to_s
    end
    if (iter % 100000 == 0)
      puts "Iter is now: " + iter.to_s
    end 
    iter = iter + 1
  end
  xmlfile.puts "</root>"
  xmlfile.close
  # Delete the master XML file - no longer need it
  File.delete(dlfile[0..-4] + "xml")
end

# XML Parsed out. Now determine specific DTDs for conversion from XML to CSV:
if (action == "full" or action == "csv")
  if type == "a"
    case fileyear.to_i
    when 2002..2004
      foo
    when 2005..2011
      #code
    when 2012..2014
      FIELDS = %w{appno pubdate pubnum title abstract invs assignee xref filedate govint parentcase childcase date371 pctpubno}
      def new_patentapp(csv, appno, pubdate, pubnum, title, abstract, invs, assignee, xref, filedate, govint, parentcase, childcase, date371, pctpubno)
        patentapps = []
        patentapps << appno
        patentapps << pubdate
        patentapps << pubnum
        patentapps << title
        patentapps << abstract
        patentapps << invs
        patentapps << assignee
        patentapps << xref
        patentapps << filedate
        patentapps << govint
        patentapps << parentcase # parent-doc
        patentapps << childcase # child case
        patentapps << date371 # us-371c124-date
        patentapps << pctpubno # parent-pct-document 
        row =  CSV::Row.new(FIELDS, patentapps)
        csv << row
      end  
    else
        #code
    end
    
    outputfile = dlfile[3..-4] + writefileprefix + ".csv" 
    csv = CSV.open(outputfile,"w")
    csv << FIELDS
    fxml = File.open(dlfile[3..-4] + writefileprefix + ".xml")  
    # Now convert the XML to CSV
    doc = Nokogiri::XML(fxml)
    # us-patent-application is the root tag for apps v4.3 and 2006
    doc.xpath('.//us-patent-application').each do |papp|
      # input fields: pubdate, title, appno, abstract, invs, xref, filedate, govint, relpatdocs, parentcase, date371, pctpubno
      processinstr1 = '<?federal-research-statement description="Federal Research Statement" end="lead"?>'
      processinstr2 = '<?federal-research-statement description="Federal Research Statement" end="tail"?>'
      # Check that there is a federal research statement. If so, continue, if not, jump to next patent app
      if papp.to_s.match(/#{Regexp.escape(processinstr1)}(.*)#{Regexp.escape(processinstr2)}/m).nil?
        next
      end
      # Publication Date of published Application doc - valid for 4.3 and 2006
      pubdate_loop = papp.xpath(".//publication-reference/document-id/date/text()").to_s
      puts "Doc Date: " + pubdate_loop
      # Publication Number (the unique number given to the published application document)
      pubnum_loop = papp.xpath("./us-bibliographic-data-application/publication-reference/document-id/doc-number/text()").to_s
      # Title - valid for 4.3 and 2006
      title_loop = papp.xpath('.//invention-title/text()').to_s
      puts "Title: " + title_loop + "\n"
      # Application Number (AKA Serial Number) - valid for 4.3 and 2006
      appno_loop = papp.xpath(".//application-reference/document-id/doc-number/text()").to_s
      puts "Application No.: " + appno_loop
      # Abstract - valid for 4.3 and 2006
      abstract_loop = papp.xpath(".//abstract/p/text()").to_s
      puts "Abstract text: " + abstract_loop
      # Inventors
      ## Inventors for 2006 format:
      invs_loop = ""
      if (fileyear.to_i < 2007)
        papp.xpath('.//applicant').each do |inventor|
          # concatenate all the inventors names together (first last) and separate with an underscore
          invs_loop = invs_loop+ "[" + inventor.xpath('.//first-name/text()').to_s + " " + inventor.xpath('.//last-name/text()').to_s + "]"
        end
      end
      ## Inventors for 2007 + format (watch - AIA "Applicants" need not be a person)
      if (fileyear.to_i >= 2007)
        papp.xpath('.//inventor/addressbook').each do |inventor|
          # concatenate all the inventors names together (first last) and separate with an underscore
          invs_loop = invs_loop+ "[" + inventor.xpath('.//first-name/text()').to_s + " " + inventor.xpath('.//last-name/text()').to_s + "]"
        end
      end
      # Cross-Reference - not all apps will have a cross reference (xref) so check first
      # Valid for 4.3 and 2006
      # again, this is coded via processing instructions, so cant reliably use XPATH to search this
      processxref1 = '<?cross-reference-to-related-applications description="Cross Reference To Related Applications" end="lead"?>'
      processxref2 = '<?cross-reference-to-related-applications description="Cross Reference To Related Applications" end="tail"?>'
      if not(papp.to_s.match(/#{Regexp.escape(processxref1)}(.*)#{Regexp.escape(processxref2)}/m).nil?)
        xref_loop = papp.to_s.match(/#{Regexp.escape(processxref1)}(.*)#{Regexp.escape(processxref2)}/m)[1].strip
        pgovint = Nokogiri::XML.fragment(xref_loop)
        xref_loop = pgovint.xpath("./p/text()").to_s
        puts "CROSS REFERENCE via PI" + xref_loop
      elsif not(papp.xpath(".//description/heading[contains(.,'CROSS-REFERENCE') or contains(.,'CROSSREF') or contains(.,'CROSS REFERENCE')]").nil?)
        # If there is no processing instruction, then try at least to see if there is a CROSS REF header
        xref_loop = papp.xpath(".//description/heading[contains(.,'CROSS-REFERENCE') or contains(.,'CROSSREF') or contains(.,'CROSS REFERENCE')]/following-sibling::*[1]/text()").to_s
        puts "CROSS REFERENCE via string search" + xref_loop
      else
        puts "No Cross-Ref found"
        xref_loop = ""
      end
      # Filing Date of Application - valid for 4.3 and 2006
      filedate_loop = papp.xpath(".//application-reference/document-id/date/text()").to_s
      puts "Filing Date of Application: " + filedate_loop
      # Government Interest (NSF grant number Stuff) - it is enclosed in processing instructions!! So cant easily XPATH parse it
      # Valid for 4.3 and 2006
      govint_loop = papp.to_s.match(/#{Regexp.escape(processinstr1)}(.*)#{Regexp.escape(processinstr2)}/m)[1].strip
      ## this gives us at least the <p> element. Now get the text from inside that
      pgovint = Nokogiri::XML.fragment(govint_loop)
      govint_loop = pgovint.xpath("./p/text()").to_s
      if not(govint_loop.include? " NSF " or govint_loop.include? "National Science Foundation" or
             govint_loop.include? " NSF" or govint_loop.include? "NSF ")
        # then this is not an NSF patent application - go to next XML doc
        next
      end
      puts "Government Interest: " + govint_loop
      # Parent Case - if exists - valid for 4.3 and 2006
      parentcase_loop = ""
      parentcase_loop = papp.xpath(".//us-related-documents//parent-doc/document-id/doc-number/text()").first.to_s
      puts "Parent case: " + parentcase_loop
      # Child Case - if exists - valid for 4.3
      childcase_loop = ""
      childcase_loop = papp.xpath(".//us-related-documents//child-doc/document-id/doc-number/text()").first.to_s
      puts "Child case: " + childcase_loop
      # 371 Date - if exists - valid for 4.3 and 2006
      date371_loop = papp.xpath(".//us-371c124-date/date/text()").to_s
      puts "371 date: " + date371_loop
      # PCT Publication Number - if exists - valid for 4.3 and 2006
      # - check first that country code is WO, this means its a PCT published app
      if papp.xpath(".//pct-or-regional-filing-data/document-id/country/text()").to_s == "WO"
        pctpubno_loop = papp.xpath(".//pct-or-regional-filing-data/document-id/doc-number/text()").to_s
      else
        pctpubno_loop = ""
      end
      puts "PCT Pub No.: " + pctpubno_loop
      case fileyear.to_i
        when 2012..2014
          assignee_loop = ""
          papp.xpath('.//assignees/assignee').each do |assig|
            # concatenate all the assignees together (first last) and separate with square brackets
            assignee_loop = assignee_loop + "[" + assig.xpath('./addressbook/orgname/text()').to_s + "]"
          end
          puts "Assignee: " + assignee_loop
          new_patentapp(csv, appno_loop, pubdate_loop, pubnum_loop, title_loop, abstract_loop, invs_loop, assignee_loop, xref_loop, filedate_loop,
                    govint_loop, parentcase_loop, childcase_loop, date371_loop, pctpubno_loop)
        else
      end
    end    
  end
  if type == "p"
    case fileyear.to_i
    when 2002..2004
      foo
    when 2005..2011
      #code
    when 2012..2014
      FIELDS = %w{patentno patpubdate title appno priorpub priorpubdate abstract invs assignee xref filedate govint parentcase childcase date371 pctpubno}
      def new_patent(csv, patentno, patpubdate, title, appno, priorpub, priorpubdate, abstract, invs, assignee, xref, filedate, govint, parentcase, childcase, date371, pctpubno)
        patent = []
        patent << patentno
        patent << patpubdate
        patent << title
        patent << appno
        patent << priorpub
        patent << priorpubdate
        patent << abstract
        patent << invs
        patent << assignee
        patent << xref
        patent << filedate
        patent << govint
        patent << parentcase # parent-doc
        patent << childcase # childcase
        patent << date371 # us-371c124-date
        patent << pctpubno # parent-pct-document 
        row =  CSV::Row.new(FIELDS, patent)
        csv << row
      end  
    else
        #code
    end
    outputfile = dlfile[3..-4] + writefileprefix + ".csv" 
    csv = CSV.open(outputfile,"w")
    csv << FIELDS
    fxml = File.open(dlfile[3..-4] + writefileprefix + ".xml")  
    # Now convert the XML to CSV
    doc = Nokogiri::XML(fxml)
    # us-patent-grant is the root tag for apps v4.3
    doc.xpath('.//us-patent-grant').each do |papp|
      processinstr1 = '<?GOVINT description="Government Interest" end="lead"?>'
      processinstr2 = '<?GOVINT description="Government Interest" end="tail"?>'
      # Check that there is a federal research statement. If so, continue, if not, jump to next patent app
      if papp.to_s.match(/#{Regexp.escape(processinstr1)}(.*)#{Regexp.escape(processinstr2)}/m).nil?
        next
      end
      # Issued PAtent number
      patno_loop = papp.xpath(".//publication-reference/document-id/doc-number/text()").to_s
      # Publication Date of published Patent doc - valid for 4.3
      patpubdate_loop = papp.xpath(".//publication-reference/document-id/date/text()").to_s
      puts "Doc Date: " + patpubdate_loop
      # Title - valid for 4.3
      title_loop = papp.xpath('.//invention-title/text()').to_s
      puts "Title: " + title_loop + "\n"
      # Application Number (AKA Serial Number) - valid for 4.3 and 2006
      appno_loop = papp.xpath(".//application-reference/document-id/doc-number/text()").to_s
      puts "Application No.: " + appno_loop
      # Prior Publication Document Number
      priorpub_loop = papp.xpath(".//related-publication/document-id/doc-number/text()").to_s
      # Prior Publication Document pub date
      priorpubdate_loop = papp.xpath(".//related-publication/document-id/date/text()").to_s
      # Abstract - valid for 4.3
      abstract_loop = papp.xpath(".//abstract/p/text()").to_s
      puts "Abstract text: " + abstract_loop
      # Inventors
      ## Inventors for 2006 format:
      invs_loop = ""
      if (fileyear.to_i < 2007)
        papp.xpath('.//applicant').each do |inventor|
          # concatenate all the inventors names together (first last) and separate with an underscore
          invs_loop = invs_loop+ "[" + inventor.xpath('.//first-name/text()').to_s + " " + inventor.xpath('.//last-name/text()').to_s + "]"
        end
      end
      ## Inventors for 2007 + format (watch - AIA "Applicants" need not be a person)
      if (fileyear.to_i >= 2007)
        papp.xpath('.//inventor/addressbook').each do |inventor|
          # concatenate all the inventors names together (first last) and separate with an underscore
          invs_loop = invs_loop+ "[" + inventor.xpath('.//first-name/text()').to_s + " " + inventor.xpath('.//last-name/text()').to_s + "]"
        end
      end
      # Cross-Reference - not all apps will have a cross reference (xref) so check first
      # Valid for 4.3 and 2006
      # again, this is coded via processing instructions, so cant reliably use XPATH to search this
      processxref1 = '<?RELAPP description="Other Patent Relations" end="lead"?>'
      processxref2 = '<?RELAPP description="Other Patent Relations" end="tail"?>'
      if not(papp.to_s.match(/#{Regexp.escape(processxref1)}(.*)#{Regexp.escape(processxref2)}/m).nil?)
        xref_loop = papp.to_s.match(/#{Regexp.escape(processxref1)}(.*)#{Regexp.escape(processxref2)}/m)[1].strip
        pgovint = Nokogiri::XML.fragment(xref_loop)
        xref_loop = pgovint.xpath("./p/text()").to_s
        puts "CROSS REFERENCE via PI" + xref_loop
      elsif not(papp.xpath(".//description/heading[contains(.,'CROSS-REFERENCE') or contains(.,'CROSSREF') or contains(.,'CROSS REFERENCE')]").nil?)
        # If there is no processing instruction, then try at least to see if there is a CROSS REF header
        xref_loop = papp.xpath(".//description/heading[contains(.,'CROSS-REFERENCE') or contains(.,'CROSSREF') or contains(.,'CROSS REFERENCE')]/following-sibling::*[1]/text()").to_s
        puts "CROSS REFERENCE via string search" + xref_loop
      else
        puts "No Cross-Ref found"
        xref_loop = ""
      end
      # Filing Date of Application - valid for 4.3 
      filedate_loop = papp.xpath(".//application-reference/document-id/date/text()").to_s
      puts "Filing Date of Application: " + filedate_loop
      # Government Interest (NSF grant number Stuff) - it is enclosed in processing instructions!! So cant easily XPATH parse it
      # Valid for 4.3 and 2006
      govint_loop = papp.to_s.match(/#{Regexp.escape(processinstr1)}(.*)#{Regexp.escape(processinstr2)}/m)[1].strip
      ## this gives us at least the <p> element. Now get the text from inside that
      pgovint = Nokogiri::XML.fragment(govint_loop)
      govint_loop = pgovint.xpath("./p/text()").to_s
      if not(govint_loop.include? " NSF " or govint_loop.include? "National Science Foundation" or
             govint_loop.include? " NSF" or govint_loop.include? "NSF ")
        # then this is not an NSF patent application - go to next XML doc
        next
      end
      puts "Government Interest: " + govint_loop
      # Parent Case - if exists - valid for 4.3
      parentcase_loop = ""
      parentcase_loop = papp.xpath(".//us-related-documents//parent-doc/document-id/doc-number/text()").first.to_s
      puts "Parent case: " + parentcase_loop
      # Child Case - if exists - valid for 4.3
      childcase_loop = ""
      childcase_loop = papp.xpath(".//us-related-documents//child-doc/document-id/doc-number/text()").first.to_s
      puts "Child case: " + childcase_loop
      # 371 Date - if exists - valid for 4.3 and 2006
      date371_loop = papp.xpath(".//us-371c124-date/date/text()").to_s
      puts "371 date: " + date371_loop
      # PCT Publication Number - if exists - valid for 4.3 and 2006
      # - check first that country code is WO, this means its a PCT published app
      if papp.xpath(".//pct-or-regional-filing-data/document-id/country/text()").to_s == "WO"
        pctpubno_loop = papp.xpath(".//pct-or-regional-filing-data/document-id/doc-number/text()").to_s
      else
        pctpubno_loop = ""
      end
      puts "PCT Pub No.: " + pctpubno_loop
      case fileyear.to_i
        when 2012..2014
          assignee_loop = ""
          papp.xpath('.//assignees/assignee').each do |assig|
            # concatenate all the assignees together (first last) and separate with square brackets
            assignee_loop = assignee_loop + "[" + assig.xpath('./addressbook/orgname/text()').to_s + "]"
          end
          puts "Assignee: " + assignee_loop
          new_patent(csv, patno_loop, patpubdate_loop, title_loop, appno_loop, priorpub_loop, priorpubdate_loop, abstract_loop, invs_loop, assignee_loop, xref_loop,
                     filedate_loop, govint_loop, parentcase_loop, childcase_loop, date371_loop, pctpubno_loop)
        else
      end
    end # end the per patent doc iteration
  end
  
  
end


puts "Time to complete " + action.to_s + " Action:" + (Time.now - timecounter).to_s
