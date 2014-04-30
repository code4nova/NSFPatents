def setTags(self, year):
        print 'Year is %s' % year
        if year >= 07:
            # 2007 tagslist
            self.ipa_enclosing = 'us-patent-application'
            self.ipa_pubnum = 'publication-reference/document-id/doc-number'
            self.ipa_pubdate = 'publication-reference/document-id/date' #Published patent document
            self.ipa_invtitle = 'invention-title' #Title of invention
            self.ipa_abstract = 'abstract/p' # Concise summary of disclosure
            self.ipa_assignee = 'assignees/assignee'
            self.ipa_inventors = 'applicants' # Applicants information
            self.ipa_crossref = '<?cross-reference-to-related-applications description="Cross Reference To Related Applications" end="lead"?><?cross-reference-to-related-applications description="Cross Reference To Related Applications" end="tail"?>' # Xref, but there is also a 2nd option coded into the scrape method
            self.ipa_appnum = 'application-reference/document-id/doc-number' # Patent ID
            self.ipa_appdate = 'application-reference/document-id/date' # Filing Date
            self.ipa_pct_371cdate = 'pct-or-regional-filing-data/us-371c124-date' # PCT filing date
            self.ipa_pct_pubnum = 'pct-or-regional-publishing-data/document-id/doc-number' # PCT publishing date
            self.ipa_priorpub = 'related-publication/document-id/doc-number' # Previously published document about same app
            self.ipa_priorpubdate = 'related-publication/document-id/date' # Date for previously published document
            self.ipa_govint = '<?federal-research-statement description="Federal Research Statement" end="lead"?><?federal-research-statement description="Federal Research Statement" end="tail"?>' #Govint
            self.ipa_parentcase = 'us-related-documents/parent-doc/document-id/doc-number' # Parent Case
            self.ipa_childcase = 'us-related-documents/child-doc/document-id/doc-number' # Child Case

            self.ipg_enclosing = 'us-patent-grant'
            self.ipg_govint = '<?GOVINT description="Government Interest" end="lead"?><?GOVINT description="Government Interest" end="tail"?>'
            self.ipg_crossref = '<?RELAPP description="Other Patent Relations" end="lead"?><?RELAPP description="Other Patent Relations" end="tail"?>'


