#!/usr/bin/env ruby1.8
require 'optparse'
require 'ostruct'
require 'log4r'
require 'pp'
include Log4r
require File.dirname(__FILE__) + '/keysymdef.rb'
include Keysymdef

#require 'unprof'

module Enumerable
  # [1,2,3] -> [[1,2],[1,3],[2,3]]
  def each_pair()
    self.each_with_index do |item1, i|
      self[(i+1)..self.size].each do |item2|
        yield([item1, item2])
      end
    end
  end

  def each_prefix()
    0.upto(self.size-1-1) do |i|
      yield self[0..i]
    end
  end

end


# Parser for XCompose compose definitions.
#
# TODO: - includes
#       - "\nnn" description format
class XComposeParser
  attr_accessor :file, :parsed_lines, :logger

  # Index to speed mapping prefix checks.
  #
  # The format is mapping => [parser, lineno]
  @@map_index = {}
  def self.map_index
    @@map_index
  end

  class MapDuplicate < StandardError
  end
  class MapConflict < StandardError
  end
  class MapPrefixConflict < MapConflict
  end
  class ParseError < StandardError
    def initialize(file)
      super("Parse error at file #{@file.path}:#{@file.lineno}.")
    end
  end


  def initialize(file, logger=nil)

    if not file.respond_to? :read
      file = File.open(file.to_str, 'r')
    end
    @file = file

    if logger
      @logger = Logger.new(logger.fullname + '::' + \
                           "parser:#{@file.path}")
    else
      @logger = Logger.new("parser:#{@file.path}")
      @logger.outputters << Outputter.stdout
      @logger.level = DEBUG
    end
    @parsed_lines = []
  end


  # Parse the file and fill @parsed_lines.
  def parse
    @file.seek 0

    @file.each_line do |line|
      pline = nil

      if line.match(/^#/)
        @logger.debug("Skipped comment at line #{@file.lineno}")
      elsif line.match(/^\s*$/)
        @logger.debug("Skipped blank line at line #{@file.lineno}")
      elsif line.match(/^\s*include/)
        @logger.warn("Skipped include at line #{@file.lineno}")
      elsif line.index(':')
        pline = self.class.parse_line(line)
        if not pline
          raise ParseError.new(@file)
        else
          @parsed_lines[@file.lineno] = pline
        end
      else
        raise ParseError.new(@file)
      end

      next if not pline
      if not (@@map_index.has_key?(pline[:map]))
        @@map_index[pline[:map]] = [self, @file.lineno]
      else # mapping already indexed!
        dup_parser, dup_index = @@map_index[pline[:map]]
        dup_pline = dup_parser.parsed_lines[dup_index]
        if pline[:definition] == dup_pline[:definition]
          raise MapDuplicate.new(format("%s:%d: duplicate map: %s:%d",
                                        @file.path, @file.lineno,
                                        dup_parser.file.path, dup_index))
        else
          raise MapConflict.new(format("%s:%d: map conflict: %s:%d",
                                       @file.path, @file.lineno,
                                       dup_parser.file.path, dup_index))

        end
      end
    end
  end

  # Parse a singe XCompose line.
  #
  # Returns a hash with :map, :definition, :description, and :comment.
  def self.parse_line(line)
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


  class InvalidCodepoint < StandardError
    def initialize(invcd)
      super(invcd + " doesn't look like a codepoint")
    end
  end

  class UnknownKeysymname < StandardError
    def initialize(keysymname)
      super(format("Couldn't find keysym name `%s' in database", keysymname))
    end
  end

  class DescriptionConflict < StandardError
    def initialize(parsed_line)
      super(format("Description `%s' doesn't match definition `%s'",
                   parsed_line[:description],
                   parsed_line[:definition]))

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
      keysymval = Keysyms[desc]
      if not  keysymval
        raise UnknownKeysymname.new(desc)
      elsif defin != keysymval
        raise DescriptionConflict.new(parsed_line)
      else
        return true
      end
    end
  end

  def validate_descs()
    valid=true
    0.upto(@parsed_lines.size) do |i|
      next if not @parsed_lines[i]
      begin
        self.class.validate_desc(@parsed_lines[i])
        @logger.debug("#{i}: description valid.")
      rescue UnknownKeysymname, DescriptionConflict, InvalidCodepoint => ex
        @logger.error("#{i}: #{ex.message}")
        valid = false
      end
    end
    return valid
  end

  def validate_mapping(li)
    l = @parsed_lines[li]
    return true if not l
    l[:map].each_prefix do |pref|
      conflict = @@map_index[pref]
      if conflict
        raise MapPrefixConflict.new(format("%s:%s: prefix conflict with %s:%s",
                                           @file.path, li,
                                           conflict[0].file.path, conflict[1]))
      end
    end
    return true
  end

end


if __FILE__ == $0
  options = OpenStruct.new
  OptionParser.new {|op|
    op.banner = "Usage: #{$0} [options] <Compose files...>"
    op.on('v', '--verbose', 'Increase verbosity') do |v|
      options.verbose = v
    end
  }.parse!

  exit 1 if not ARGV[0]
  ARGV.each do |fpath|
    if not File.readable? fpath
      $stderr.puts "Cannot read file #{fpath}"
      exit 1
    end
  end

  l = Logger.new('xcompose_parser')
  if options.verbose
    l.level=DEBUG
  else
    l.level=INFO
  end
  l.outputters << Outputter.stdout


  l.info("Checking syntax and mappings...")
  parsers=[]
  ARGV.each do |fpath|
    p = XComposeParser.new(fpath, l)
    begin
      p.parse
      p.logger.info("Parsed fine.")
      parsers << p
    rescue XComposeParser::MapDuplicate => ex
      l.warn(ex.message)
      parsers << p
    rescue XComposeParser::ParseError, XComposeParser::MapConflict => ex
      l.error(ex.message)
      l.info("#{p.file.path} will be skipped")
    end
  end

  l.info("Checking for bad descriptions...")

  parsers.each do |p|
    if p.validate_descs
      p.logger.info("Descriptions ok.")
    else
      p.logger.error("Description errors.")
    end
  end

  l.info("Checking for mapping conflicts...")

  parsers.each do |p|
    p.parsed_lines.each_index do |i|
      begin
        p.validate_mapping(i)
      rescue XComposeParser::MapConflict => ex
        p.logger.error(ex.message)
      end
    end
  end
end
