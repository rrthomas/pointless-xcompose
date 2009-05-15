#!/usr/bin/env ruby1.8

require File.dirname(__FILE__) + '/keysymdef.rb'

# Parser for XCompose compose definitions.
#
# Does not do includes.
class XComposeParser
  attr_accessor :file, :parsed_lines

  # Parse a singe XCompose line.
  #
  # Returns a hash with :map,
  # :definition, :description and :comment, or nil if the line wasn't
  # a Compose mapping.
  def self.parse_line(line)
    return if (not line.index(':') \
               or line.match(/^#/) \
               or line.match(/^\s*include/))

    map_side, definition_side = line.split ':'
    definition, comment = definition_side.split '#'
    defchar, defdesc = definition.split(/\s/).reject {|s| s.empty?}

    parsed = {}

    parsed[:map] = map_side.split(/\s/).reject {|s| s.empty?}.each do |s|
      s.strip
    end

    defin = defchar.strip.sub(/^["']/,'').sub(/["']$/,'')
    # unquote definition
    if defin == '\\"'
      parsed[:definition] = '"'
    elsif defin == '\\\\'
      parsed[:definition] = '\\'
    else
      parsed[:definition] = defin
    end
    
    parsed[:description] = defdesc.strip if defdesc
    parsed[:comment] = comment.strip if comment

    parsed
  end

  # Utility function to convert a codepoint like U+nnn or Unnnn to
  # UTF-8 string.
  def self.codepoint_to_unichar(codepoint)
    # get an integer out of codepoint
    if not codepoint.kind_of? Integer
      if codepoint.respond_to? :to_str
        if m=codepoint.match(/^U\+?([0-9abcdef]+)$/i)
          codepoint = m[1].to_i(16)
        else
          raise ArgumentError.new(codepoint)
        end
      else
        codepoint = codepoint.to_i
      end
    end

    [codepoint].pack('U')
  end

  # Returns false if a parsed line's description conflicts with its
  # definition, true otherwise.
  #
  # Raises ArgumentError if an unknown keysymname is found.
  def self.validate_desc(parsed_line)
    desc, defin = parsed_line[:description], parsed_line[:definition]

    return true if (not desc or not defin)
    if desc.match(/^U\+?[0-9A-F]+$/i) # if unicode description
      if (defin == codepoint_to_unichar(desc))
        return true
      else
        return false
      end
    else # keysymname description
      keysymval = Keysymdef::Keysyms[desc]
      if not keysymval
        raise ArgumentError.new("Unknown keysymname #{desc}")
      elsif defin == keysymval
        return true
      else
        return false
      end
    end
  end


  def initialize(file)
    if not file.respond_to? :read and file.respond_to? :to_str
      file = File.open(file, 'r')
    end
    @file = file
    @parsed_lines = []
    self.parse
  end

  def parse
    @file.seek 0
    @file.each_line do |line|
      parsed = self.class.parse_line(line)
      if parsed
        @parsed_lines[@file.lineno] = parsed
        # TODO: log skipped lines
      end
    end
  end

  def validate_desc(n)
    self.class.validate_desc(@parsed_lines[n])
  end

end

if __FILE__ == $0
  exit if not ARGV[0]
  p = XComposeParser.new(ARGV[0])

  valid=true
  0.upto(p.parsed_lines.size).each do |i|
    next if not p.parsed_lines[i]
    if not p.validate_desc(i)
      puts(format '%d: invalid (description: "%s", definition: "%s")',
           i,
           p.parsed_lines[i][:description],
           p.parsed_lines[i][:definition])
      valid=false
    end
  end
  if valid
    puts "All ok."
  else
    puts "There were errors."
    exit 1
  end
end
