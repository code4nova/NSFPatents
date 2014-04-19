#!/usr/bin/env ruby
# Must run under Ruby 1.9+ or the CSV parsing signatures are different
require 'rubygems'
require 'nokogiri'
require 'csv'

# Program runs in this format: ruby <filename> Ò<input>Ó 
 
FIELDS = %w{pubdate title appno abstract invs xref filedate govint relpatdocs parentcase date371 pctpubno}
 
def new_patentapp(csv, pubdate, title, appno, abstract, invs, xref, filedate, govint, relpatdocs, parentcase, date371, pctpubno)
 
  patentapps = []
  patentapps << pubdate
  patentapps << title
  patentapps << appno
  patentapps << abstract
  patentapps << invs
  patentapps << xref
  patentapps << filedate
  patentapps << govint
  # patentapps << priorpub # related-publication
  patentapps << relpatdocs # related-publication
  patentapps << parentcase # parent-doc
  #patentapps << pctfiledate
  #patentapps << pctappno
  patentapps << date371 # us-371c124-date
  patentapps << pctpubno # parent-pct-document
  #patentapps << p: ctpubdate
 
  row =  CSV::Row.new(FIELDS, patentapps)
  csv << row
end 
 
outputfile = ARGV[0][0..12]+"s.csv" 
csv = CSV.open(outputfile,"w")
csv << FIELDS

# The XML will be improperly formatted with extra <?XML tags throughout and no root node. Fix this
xmldocstr = ""
f = File.open(ARGV[0])
    f.each_with_index do |line, j|
      if j == 0
        xmldocstr = xmldocstr + line.to_s
        next
      elsif j == 1
        xmldocstr = xmldocstr + "<root>"
        next
      end
      if (line.include? "<?xml version=" or line.include? "<!DOCTYPE")
        next
      else
        xmldocstr = xmldocstr + line.to_s
      end
    end
 
doc = Nokogiri::XML(xmldocstr)

numpapps = doc.xpath('count(//us-patent-application)')
puts "number of apps: " + numpapps.to_s
 
doc.xpath('.//us-patent-application').each do |papp|
  # input fields: pubdate, title, appno, abstract, invs, xref, filedate, govint, relpatdocs, parentcase, date371, pctpubno
  processinstr1 = '<?federal-research-statement description="Federal Research Statement" end="lead"?>'
  processinstr2 = '<?federal-research-statement description="Federal Research Statement" end="tail"?>'
  # Check that there is a federal research statement. If so, continue, if not, jump to next patent app
  if papp.to_s.match(/#{Regexp.escape(processinstr1)}(.*)#{Regexp.escape(processinstr2)}/m).nil?
    next
  end
  # Publication Date of published Application doc
  pubdate_loop = papp.xpath(".//publication-reference/document-id/date/text()").to_s
  puts "Doc Date: " + pubdate_loop
  # Title
  title_loop = papp.xpath('.//invention-title/text()').to_s
  puts "Title: " + title_loop + "\n"
  # Application Number (AKA Serial Number)
  appno_loop = papp.xpath(".//application-reference/document-id/doc-number/text()").to_s
  puts "Application No.: " + appno_loop
  # Abstract
  abstract_loop = papp.xpath(".//abstract/p/text()").to_s
  puts "Abstract text: " + abstract_loop
  # Inventors
  invs_loop = ""
  papp.xpath('.//applicant').each do |inventor|
    # concatenate all the inventors names together (first last) and separate with an underscore
    invs_loop = invs_loop+ "[" + inventor.xpath('.//first-name/text()').to_s + " " + inventor.xpath('.//last-name/text()').to_s + "]"
  end
  # Cross-Reference - not all apps will have a cross reference (xref) so check first
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
  # Filing Date of Application
  filedate_loop = papp.xpath(".//application-reference/document-id/date/text()").to_s
  puts "Filing Date of Application: " + filedate_loop
  # Government Interest (NSF grant number Stuff) - it is enclosed in processing instructions!! So cant easily XPATH parse it
  govint_loop = papp.to_s.match(/#{Regexp.escape(processinstr1)}(.*)#{Regexp.escape(processinstr2)}/m)[1].strip
  ## this gives us at least the <p> element. Now get the text from inside that
  pgovint = Nokogiri::XML.fragment(govint_loop)
  govint_loop = pgovint.xpath("./p/text()").to_s
  puts "Government Interest: " + govint_loop
  # Related Publications - check if exists first
  relpatdocs_loop = papp.xpath(".//related-publication/document-id/doc-number/text()").to_s
  puts "Related patent doc: " + relpatdocs_loop
  # Parent Case - if exists
  parentcase_loop = papp.xpath(".//us-related-documents//parent-doc/document-id/doc-number/text()").to_s
  puts "Parent case: " + parentcase_loop
  # 371 Date - if exists
  date371_loop = papp.xpath(".//us-371c124-date/date/text()").to_s
  puts "371 date: " + date371_loop
  # PCT Publication Number - if exists
  # - check first that country code is WO, this means its a PCT published app
  if papp.xpath(".//pct-or-regional-filing-data/document-id/country/text()").to_s == "WO"
    pctpubno_loop = papp.xpath(".//pct-or-regional-filing-data/document-id/doc-number/text()").to_s
  else
    pctpubno_loop = ""
  end
  puts "PCT Pub No.: " + pctpubno_loop
  new_patentapp(csv, pubdate_loop, title_loop, appno_loop, abstract_loop, invs_loop, xref_loop, filedate_loop,
                govint_loop, relpatdocs_loop, parentcase_loop, date371_loop, pctpubno_loop)
end