require 'nokogiri'
require 'mechanize'
require 'open-uri'
# Saving data:
# unique_keys = [ 'id' ]
# data = { 'id'=>12, 'name'=>'violet', 'age'=> 7 }
# ScraperWiki.save_sqlite(unique_keys, data)
# First get patent application from USPTO:
docid = "20120304323"
moredatalink = "http://appft.uspto.gov/netacgi/nph-Parser?Sect1=PTO2&Sect2=HITOFF&u=%2Fnetahtml%2FPTO%2Fsearch-adv.html&r=1&p=1&f=G&l=50&d=PG01&S1=" + docid + ".PGNR.&OS=DN/" + docid + "&RS=DN/" + docid
morebeesdata = open(moredatalink)
morebeesdoc = Nokogiri::HTML(morebeesdata)
# Now we have the document for this particular patent. What fields do we want?
#Assignee
title = morebeesdoc.search("//font[@size='+1'][1]/text()")
assigneebee = morebeesdoc.search("//th[contains(text(),'Assignee')][1]/following-sibling::td[1]/b[1]/text()").to_s

puts title
puts assigneebee
url = "http://www.research.gov/research-portal/appmanager/base/desktop?_nfpb=true&_eventName=viewQuickSearchFormEvent_so_rsr"
ag = Mechanize.new
page = ag.get(url)
form = page.forms[1] # return the second form
# Assume we've grabbed the grant number
grantid = "0912837"
form['federalAwardId'] = grantid
# The response should be the summary of the NSF grant - another HTML page
grantdetail = form.submit
a = Mechanize.new
fullgrantdetail = a.click(grantdetail.link_with(:text => grantid))
awardee = fullgrantdetail.search("//td[contains(text(),'Awardee:')][1]/following-sibling::td[1]/text()").to_s
dbaname = fullgrantdetail.search("//td[contains(text(),'Doing Business As Name:')][1]/following-sibling::td[1]/text()").to_s
pdpi = fullgrantdetail.search("//td[contains(text(),'PD/PI:')][1]/following-sibling::td[1]/text()").to_s
awarddate = fullgrantdetail.search("//td[contains(text(),'Award Date:')][1]/following-sibling::td[1]/text()").to_s
estawardamt = fullgrantdetail.search("//td[contains(text(),'Estimated Total Award Amount:')][1]/following-sibling::td[1]/text()").to_s
fundstodate = fullgrantdetail.search("//td[contains(text(),'Funds Obligated to Date:')][1]/following-sibling::td[1]/text()").to_s
awardstartdate = fullgrantdetail.search("//td[contains(text(),'Award Start Date:')][1]/following-sibling::td[1]/text()").to_s
awardexpdate = fullgrantdetail.search("//td[contains(text(),'Award Expiration Date:')][1]/following-sibling::td[1]/text()").to_s
awardtranstype = fullgrantdetail.search("//td[contains(text(),'Transaction Type:')][1]/following-sibling::td[1]/text()").to_s
awardtitle = fullgrantdetail.search("//td[contains(text(),'Award Title or Description:')][1]/following-sibling::td[1]/text()").to_s
dunsid = fullgrantdetail.search("//td[contains(text(),'DUNS ID:')][1]/following-sibling::td[1]/text()").to_s
program = fullgrantdetail.search("//td[contains(text(),'Program:')][1]/following-sibling::td[1]/text()").to_s
programofficer = fullgrantdetail.search("//td[contains(text(),'Program Officer:')][1]/following-sibling::td[1]/text()").to_s
street = fullgrantdetail.search("//td[contains(text(),'Street:')][1]/following-sibling::td[1]/text()").to_s
city = fullgrantdetail.search("//td[contains(text(),'City:')][1]/following-sibling::td[1]/text()").to_s
state = fullgrantdetail.search("//td[contains(text(),'State:')][1]/following-sibling::td[1]/text()").to_s
zip = fullgrantdetail.search("//td[contains(text(),'ZIP:')][1]/following-sibling::td[1]/text()").to_s
county = fullgrantdetail.search("//td[contains(text(),'County:')][1]/following-sibling::td[1]/text()").to_s
country = fullgrantdetail.search("//td[contains(text(),'Country:')][1]/following-sibling::td[1]/text()").to_s
