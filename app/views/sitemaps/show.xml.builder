xml.instruct!
xml.urlset(xmlns: "http://www.sitemaps.org/schemas/sitemap/0.9") do
  urls = [ root_url, changes_url, methodology_url, data_url ] +
         @vendors.map { |vendor| vendor_url(vendor) } +
         @events.map { |event| change_url(event) }
  urls.each { |url| xml.url { xml.loc url } }
end
