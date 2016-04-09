#!/bin/env ruby
# encoding: utf-8

require 'colorize'
require 'csv'
require 'nokogiri'
require 'pry'
require 'scraperwiki'
require 'set'
require 'open-uri/cached'
OpenURI::Cache.cache_path = '.cache'

@seen = Set.new

@terms = CSV.parse(<<tdcsv, headers: true, header_converters: :symbol)
id,name,start_date,end_date,wikidata
14,XIVe législature de la Cinquième République,2012-06-20,,Q3570385
13,XIIIe législature de la Cinquième République,2007-06-20,2012-06-19,Q3025921
12,XIIe législature de la Cinquième République,2002-06-19,2007-06-19,Q3570376
11,XIe législature de la Cinquième République,1997-06-01,2002-06-18,Q3570394
10,Xe législature de la Cinquième République,1993-04-02,1997-04-21,Q3570849
9,IXe législature de la Cinquième République,1988-06-06,1993-04-01,Q3147021
8,VIIIe législature de la Cinquième République,1986-04-02,1988-05-14,Q3552944
7,VIIe législature de la Cinquième République,1981-07-02,1986-04-01,Q3552950
6,VIe législature de la Cinquième République,1978-04-03,1981-05-22,Q3552959
5,Ve législature de la Cinquième République,1973-04-02,1978-04-02,Q3555150
4,IVe législature de la Cinquième République,1968-07-11,1973-04-01,Q2380278
3,IIIe législature de la Cinquième République,1967-04-03,1968-05-30,Q3146694
2,IIe législature de la Cinquième République,1962-12-06,1967-04-02,Q3146705
1,Ire législature de la Cinquième République,1958-12-09,1962-10-09,Q3154303
tdcsv

class String
  def tidy
    self.gsub(/[[:space:]]+/, ' ').strip
  end
end

def noko_for(url)
  Nokogiri::HTML(open(url).read) rescue nil
end

def date_from(str)
  return if str.to_s.empty?
  Date.parse(str) rescue ''
end

def scrape_term(term)
  source = "http://www.assemblee-nationale.fr/sycomore/result.asp?choixordre=chrono&legislature=#{term}" 
  warn source
  noko = noko_for(source)
  noko.css('div#corps_tableau table').xpath('.//tr[td]').each do |tr|
    td = tr.css('td')
    url = URI.join(source, td[0].css('a/@href').text).to_s
    next if @seen.include? url

    data = { 
      id: url[/num_dept=(\d+)/, 1],
      name: td[0].text.tidy,
      birth_date: date_from(td[1].text.tidy).to_s,
      death_date: date_from(td[2].text.tidy).to_s,
      term: term,
      source: url,
    }
    scrape_person(url, data) 
  end
end

def scrape_person(url, data)
  noko = noko_for(url) or return
  @seen << url
  unless (img = noko.css('img.deputy-profile-picture/@src').text).empty?
    data[:image] = URI.join(url, img).to_s
  end
  noko.css('#assemblee p').reject { |p| p.text.to_s.empty? }.each do |m|
    start_date, end_date = m.css('b').remove.text.split(/ - /, 2).map { |d| date_from(d) } 
    area, group = m.text.sub(/^\s*:\s*/, '').split(/ - /, 2).map(&:tidy)

    # TODO store this data
    if group.to_s.downcase.include? 'réélu'
      warn group.to_s.cyan
      group.sub!(/réélu.*/i, '')
      group.sub!(/\s*\-\s*$/, '')
      warn group.to_s.yellow
    end

    if end_date.to_s.empty?
      term_id = "14"
    else
      midpoint = (start_date + (start_date..end_date).count / 2).to_s
      term_id = @terms.find { |t| (t[:start_date] < midpoint) && ((t[:end_date] || '9999-99-99') > midpoint) }[:id] rescue nil
      next unless term_id
    end

    tdata = data.merge({ 
      term: term_id,
      start_date: start_date.to_s,
      end_date: end_date.to_s,
      area: area,
      faction: group || '',
    })
    ScraperWiki.save_sqlite([:id, :term, :faction, :start_date], tdata)
  end
end

(46..59).to_a.reverse_each { |termid| scrape_term(termid) }
