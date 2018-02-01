require 'nokogiri'
require 'plist'
require 'pathname'

class String
  def start_with_either?(prefixes)
    prefixes.each do |prefix|
      return true if start_with?(prefix)
    end
    return false
  end
end
  
module Xlocalize
  class ::Nokogiri::XML::Document

    def filter_not_target_files(targets)
      prefixes = targets.map { |t| "#{t}/" }
      self.xpath("//xmlns:file").each { |node|
        fname = node["original"]
        node.remove if !fname.start_with_either?(prefixes) || !fname.include?(".lproj/")
      }
    end

    def filter_trans_units(prefix)
      self.xpath("//xmlns:source").each { |node|
        node.parent.remove if node.content.start_with?(prefix)
      }
    end

    def filter_plurals(project)
      plurals = {}
      self.xpath("//xmlns:file").each { |node|
        fname = node["original"]
        next if !fname.end_with?(".strings")
        fname_stringsdict = fname << 'dict'
        file_full_path = Pathname.new(project).split.first.to_s  << '/' << fname_stringsdict
        next if !File.exist?(file_full_path)
        
        translations = {}
        Plist::parse_xml(file_full_path).each do |key, val|
          transl = val["value"].select { |k, _| ['zero', 'one', 'two', 'few', 'many', 'other'].include?(k) }
          translations[key] = transl
          sel = 'body > trans-unit[id="' << key << '"]'
          node.css(sel).remove
        end
        plurals[fname_stringsdict] = translations
      }
      plurals.each { |k, _| self.css('file[original="' << k << '"]').remove }
      return plurals
    end

    def filter_empty_files
      self.xpath("//xmlns:body").each { |node|
        node.parent.remove if node.elements.count == 0
      }
    end
  end
end
