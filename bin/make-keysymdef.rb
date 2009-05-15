#!/usr/bin/env ruby1.8
module KeysymdefParser
  DefaultHeaderPath='/usr/include/X11/keysymdef.h'
  def self.parse(input_path=nil)
    input_path ||= DefaultHeaderPath

    if input_path.respond_to? :read
      input = input_path
    else
      input = File.open(input_path, 'r')
    end

    result = {}
    input.each_line do |l|

      # From the file:
      #
      #    Where a keysym corresponds one-to-one to an ISO 10646 /
      #    Unicode character, this is noted in a comment that provides
      #    both the U+xxxx Unicode position, as well as the official
      #    Unicode name of the character.
      #
      # The regexp below is derived from the file.

      if m=l.match(%r{^#define XK_(\w+)\s+0x[a-fA-F0-9]+\s*/\*\s*\(?U\+?([0-9A-Fa-f]+) .*\)?\*/\s*$})
        result[m[1]] = [m[2].to_i(16)].pack('U')
      end
    end
    result
  end
end

if __FILE__ == $0
  require 'date'

  def quote(name)
    '"' + name.gsub('\\','\\\\\\\\').gsub('"','\\"') + '"'
  end

  hash=KeysymdefParser::parse(ARGV[0])
  max_name_len = (hash.keys.map{|k| k.length}.sort)[-1]

  puts(<<EOF
# Autogenerated by #{$0} at #{Date::today}.
# First line of input file was:
# #{File.open(KeysymdefParser::DefaultHeaderPath, 'r').readline}

module Keysymdef
  Keysyms = {
EOF
  )
 

  hash.keys.sort.each do |key|
    puts(format('    %*s => %s,', -max_name_len, quote(key), quote(hash[key])))
  end
  puts "  }"
  puts "end"
end

