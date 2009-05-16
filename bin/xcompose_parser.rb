#!/usr/bin/env ruby1.8

require File.dirname(__FILE__) + '/keysymdef.rb'

# Parser for XCompose compose definitions.
#
# Does not do includes.
class XComposeParser
  attr_accessor :file, :parsed_lines

  class MapConflict < StandardError
    def initialize(parser, l1, l2)
    end
  end
  class MapPrefixConflict < StandardError
    def initialize(parser, l1, l2)
    end
  end
  class MapDuplicate < StandardError
    def initialize(parser, l1, l2)
    end
  end

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

    parsed[:original] = line # for convenience
    parsed
  end

  class InvalidCodepoint < StandardError
    def initialize(invcd)
      super(invcd + " doesn't look like a codepoint")
    end
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
          raise InvalidCodepoint.new(codepoint)
        end
      else
        codepoint = codepoint.to_i
      end
    end

    [codepoint].pack('U')
  end

  class UnknownKeysymname < StandardError
    def initialize(keysymname)
      super(format("Couldn't find keysym name `%s' in database", keysymname))
    end
  end

  class DescriptionConflict < StandardError
    def initialize(parsed_line)
      super(format("Description `%s' doesn't match definition` %s'",
                   parsed_line[:description],
                   parsed_line[:definition]))

    end
  end

  # Checks whether a parsed line's description matches its definition.
  def self.validate_desc(parsed_line)
    desc, defin = parsed_line[:description], parsed_line[:definition]

    return true if (not desc or not defin)
    if desc.match(/^U\+?[0-9A-F]+$/i) # if unicode description
      if (defin != codepoint_to_unichar(desc))
        raise DescriptionConflict.new(parsed_line)
      else
        return true
      end
    else # keysymname description
      keysymval = Keysymdef::Keysyms[desc]
      if not  keysymval
        raise UnknownKeysymname.new(desc)
      elsif defin != keysymval
        raise DescriptionConflict.new(parsed_line)
      else
        return true
      end
    end
  end


  def initialize(file)
    if not file.respond_to? :read
      file = File.open(file.to_str, 'r')
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
        # TODO: includes?
      end
    end
  end

  def validate_desc(n)
    self.class.validate_desc(@parsed_lines[n])
  end

  def validate_descs()
    valid=true
    0.upto(@parsed_lines.size) do |i|
      next if not @parsed_lines[i]
      begin
        validate_desc(i)
      rescue UnknownKeysymname, DescriptionConflict => ex
        $stderr.puts(format("In file #{@file.path}, line #{i}:"))
        $stderr.puts("  " + ex.message + "\n\n")
        valid = false
      end
    end
    return valid
  end

end

if __FILE__ == $0
  exit if not ARGV[0]
  p = XComposeParser.new(ARGV[0])

  valid = true

  if p.validate_descs
    puts "File #{p.file.path}: Descriptions ok."
  else
    puts "File #{p.file.path}: Description errors."
    valid=false
  end

  if valid
    exit 0
  else
    exit 1
  end
end
