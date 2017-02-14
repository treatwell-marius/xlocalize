require 'xlocalize/webtranslateit'
require 'colorize'
require 'nokogiri'
require 'plist'
require 'yaml'
require 'pathname'

module Xlocalize
  class Executor

    def plurals_file_name(locale)
      return locale_file_name(locale) << '_plurals.yml'
    end

    def locale_file_name(locale)
      return "#{locale}.xliff"
    end

    def export_master(wti, project, target, excl_prefix, master_lang)
      master_file_name = locale_file_name(master_lang)
      
      # hacky way to finish xcodebuild -exportLocalizations script, because
      # since Xcode7.3 & OS X Sierra script hangs even though it produces
      # xliff output
      # http://www.openradar.me/25857436
      File.delete(master_file_name) if File.exist?(master_file_name)
      system "xcodebuild -exportLocalizations -localizationPath ./ -project #{project} & sleep 0"
      while !File.exist?(master_file_name) do
        sleep(1)
      end

      purelyze(master_lang, target, excl_prefix, project)

      # Pushing master file to WebtranslateIt
      begin
        puts "Uploading master file to WebtranslateIt"
        file = File.open(master_file_name, 'r')
        plurals_file = File.open(plurals_file_name(master_lang), 'r')
        wti.push_master(file, plurals_file)
        puts "Done.".green
      rescue => err
        puts err.to_s.red
      ensure
        file.close unless file.nil?
      end if !wti.nil?
    end

    def purelyze(locale, target, excl_prefix, project)
      locale_file_name = locale_file_name(locale)
      target_prefix = "#{target}/"
      doc = Nokogiri::XML(open(locale_file_name))

      puts "Removing all files not matching required targets"
      doc.xpath("//xmlns:file").each { |node|
        fname = node["original"]
        node.remove if !fname.start_with?(target_prefix) || !fname.include?(".lproj/")
      }

      puts "Removing trans-unit's having reserverd prefix in their sources"
      doc.xpath("//xmlns:source").each { |node|
        node.parent.remove if node.content.start_with?(excl_prefix)
      }

      puts "Filtering plurals"
      plurals = {}
      doc.xpath("//xmlns:file").each { |node|
        fname = node["original"]
        next if !fname.end_with?(".strings")
        fname_stringsdict = fname << 'dict'
        file_full_path = Pathname.new(project).split.first.to_s  << '/' << fname_stringsdict
        next if !File.exist?(file_full_path)

        Plist::parse_xml(file_full_path).each do |key, val|
          values = val["value"]
          transl = values.select { |k, v| ['zero', 'one', 'few', 'other'].include?(k) }
          plurals[fname_stringsdict] = {key => transl}
          sel = 'body > trans-unit[id="' << key << '"]'
          node.css(sel).remove
        end
      }

      puts "Removing all files having no trans-unit elements after removal"
      doc.xpath("//xmlns:body").each { |node|
        node.parent.remove if node.elements.count == 0
      }

      puts "Writing modified XLIFF file to #{locale_file_name}"
      File.open(locale_file_name, 'w') { |f| f.write(doc.to_xml) }

      if !plurals.empty?
        puts "Writing plurals to plurals YAML file"
        File.open(plurals_file_name(locale), 'w') { |f| f.write({locale => plurals}.to_yaml) }
      end
    end

    def download(wti, locales)
      begin
        locales.each do |locale|
          puts "Downloading localized file for #{locale} translation"
          File.open("#{locale}.xliff", "w") {|file|
            wti.pull(file, locale)
            puts "Done.".green
          }
        end
      rescue => err
        puts err.to_s.red
      end
    end

    def import(locales)
      locales.each do |locale|
        doc = Nokogiri::XML(open("#{locale}.xliff"))

        doc.xpath("//xmlns:file").each { |node|
          file_name = node["original"]
          parts = file_name.split('/')
          name = ""
          parts.each_with_index {|part, idx|
            name += "/" if idx > 0
            if part.end_with?(".lproj")
              name += "#{locale}.lproj"
            elsif idx+1 == parts.count
              # TODO: join all parts till the last '.'
              name += "#{part.split('.')[0]}.strings"
            else
              name += part
            end
          }
          
          File.open(name, "w") {|file|
            (node > "body > trans-unit").each {|trans_unit|
              key = trans_unit["id"]
              target = (trans_unit > "target").text
              note = (trans_unit > "note").text
              note = "(No Commment)" if note.length <= 0
              
              file.write "/* #{note} */\n"
              file.write "\"#{key}\" = #{target.inspect};\n\n"
            }
          }

        }
      end
    end
  end
end
