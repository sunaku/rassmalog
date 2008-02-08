require 'net/http'
require 'digest/md5'
require 'tmpdir'
require 'cgi'
require 'rubygems'
require 'xmlsimple'
require 'tidy'

# taken from Rails core
class Array
  def group_by 
    inject([]) do |groups, element| 
      value = yield(element) 
      if (last_group = groups.last) && last_group.first == value 
        last_group.last << element 
      else 
        groups << [value, [element]] 
      end 
      groups 
    end 
  end
end

# == License: MIT
# == this code adapted by Greg Weber, originally by Scott Raymond
# http://redgreenblu.com/svn/projects/assert_valid_markup/

def errors_to_output( errors )
  errors.group_by {|error| error['line']}.
    map {|line, es| "line #{line}:\n  " <<
      ((es.length <= 3 ? es : [es[0], {'content' => '...'}, es[-1]]).
        map{|es| es['content']}.join("\n  "))
      }
end

def assert_valid_markup(fragment)
  filename = File.join Dir.tmpdir, 'markup.' + Digest::MD5.hexdigest(fragment).to_s
  begin
    response = File.open filename do |f| Marshal.load(f) end
  rescue
    response = Net::HTTP.start('validator.w3.org').post2('/check', "fragment=#{CGI.escape(fragment)}&output=xml")
    File.open( filename, 'w+') { |f| Marshal.dump response, f }
  end

  if markup_is_valid = response['x-w3c-validator-status']=='Valid'
    puts "passed" if $DEBUG
    true
  else
    "W3C ERRORS:\n" << 
      errors_to_output( XmlSimple.xml_in(response.body)['messages'][0]['msg'].
        map do |msg|
          msg['content'] = "#{CGI.unescapeHTML(msg['content'])}"
          msg
        end).join("\n")
  end
rescue SocketError
  # if we can't reach the validator service, just let the test pass
  puts "\nWARNING: could not connect to internet for w3c validation"
  false
end

def output_html_files
  Dir['output/**/*.html'].each {|file| yield file}
end

desc 'show w3c validation errors and warnings (must be online)'
task :validate do
  validate_files do |html|
    res = assert_valid_markup( html )
    if res && res != true
      puts res 
      true
    end
  end
end

desc 'show tidy html validation errors and warnings'
task :tidy do
  tidy_up do |tidy|
    if tidy.errors.first
      puts( "Tidy ERRORS:\n" <<
      errors_to_output( tidy.errors.map {|e| e.split($/)}.flatten.map do |l|
        l =~ /\s*line\s*(\d+)\s*(.*)/ || (fail "could not parse tidy error")
        {'line' => $1, 'content' => $2}
      end ).join($/) )
      true
    end
  end
end

namespace 'tidy' do
  desc 'show tidy diagnostic warnings'
  task :warn do
    tidy_up :show_warnings => true do |tidy|
      puts( tidy.diagnostics.map {|t| t.split("\n")}.flatten.
        reject {|l| l =~ /No warnings or errors/}.join($/) )
    end
  end
end

def tidy_up( opts={} )
  Tidy.open( opts ) do |tidy|
    validate_files do |html|
      tidy.clean(html)
      yield tidy
    end
  end
end

def validate_files
  puts("#{
  output_html_files do |html_file|
    errors = false
    puts "         #{html_file}"
    html = File.read( html_file )
    puts "\n\n" if yield html
  end.
    size.to_s} files validated")
end
