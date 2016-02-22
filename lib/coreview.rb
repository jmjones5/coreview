require "coreview/version"

module Coreview

require "open3"

class FileDiffBuilder
  attr_accessor :file_diffs

  def initialize lines
    diff_lines = Array.new()

    lines.each do |line|
      diff_lines << Array.new() if line.start_with? "diff --git"
      diff_lines.last << line
    end

    @file_diffs = diff_lines.map { |lines| FileDiff.new(lines) }
  end
end

class ChunkDiff
  attr_reader :starting_line_number
  attr_accessor :lines, :new_diff_lines

  def initialize lines
    @lines = lines
  end

  def new_diff_lines
    @new_diff_lines ||= @lines[1..@lines.count].reduce([]) do |array, line|
      array << line.sub(/^\+/, '') unless line.start_with? "-"
      array
    end
  end

  def starting_line_number
    @starting_line_number ||= @lines[0].match(/\+([0-9]*)/).captures.first
  end
end

class FileDiff
  attr_reader   :filename, :filetype
  attr_accessor :file_diff_lines, :chunk_diffs

  def initialize lines
    @file_diff_lines = lines
    build_chunk_diffs
  end

  def filename
    @filename ||= @file_diff_lines.first.split("/").last.chomp
  end

  def filetype
    @filetype ||= @file_diff_lines.first.split(".").last.chomp
  end

  def build_chunk_diffs
    chunk_diff_lines = Array.new()

    @file_diff_lines.each do |line|
      chunk_diff_lines << Array.new() if line.start_with? "@@"
      chunk_diff_lines.last << line unless chunk_diff_lines.last.nil?
    end

    @chunk_diffs = chunk_diff_lines.map { |lines| ChunkDiff.new(lines) }
  end
end

class Test
  def supports_filetype? filetype
    filetype.match(/^[h|m]$/)
  end
end

class SingleLineTest < Test
  def multiline?
    false
  end
end

class MultiLineTest < Test
  def multiline?
    true
  end
end

class Tester
  attr_accessor :file_diffs, :single_line_tests, :multi_line_tests, :tests

  def initialize(file_diffs, tests)
    @file_diffs        = file_diffs
    @tests             = tests
    @multi_line_tests  = @tests.select { |test| test.multiline? }
    @single_line_tests = @tests.select { |test| !test.multiline? }
  end

  def begin_tests

    @file_diffs.each do |file_diff|

      is_supported = ->(test) { test.supports_filetype? file_diff.filetype }
      multi_line_tests_for_filetype  = multi_line_tests.select(&is_supported)
      single_line_tests_for_filetype = single_line_tests.select(&is_supported)

      file_diff.chunk_diffs.each do |chunk_diff|

        lines = chunk_diff.new_diff_lines.reduce("") { |string, line| string + line }

        multi_line_tests_for_filetype.each do |multi_line_test|

          if multi_line_test.test(lines)
            prompt_user "#{file_diff.filename}:#{chunk_diff.starting_line_number}", multi_line_test.build_message(lines)
          end

        end

        single_line_tests_for_filetype.each do |single_line_test|
          chunk_diff.new_diff_lines.each do |line|

            if single_line_test.test(line)
              line_number = (chunk_diff.starting_line_number.to_i + chunk_diff.new_diff_lines.index(line)).to_s
              prompt_user "#{file_diff.filename}:#{line_number}", single_line_test.build_message(line)
            end

          end
        end

      end
    end

  end

  def prompt_user filename_line_number, build_message
    print build_message + " "
    answer = gets.chomp

    if answer =~ /[yY]/
      launch_xcode "#{filename_line_number}"
    end
  end

  def launch_xcode filename_line_number
    `echo "#{filename_line_number}" | pbcopy`
    
    `osascript \
    -e 'tell application "Xcode"' \
    -e   'activate' \
    -e   'delay 0.5' \
    -e   'tell application "System Events"' \
    -e     'keystroke "o" using {command down, shift down}' \
    -e     'keystroke "v" using {command down}' \
    -e     'keystroke return' \
    -e   'end tell' \
    -e 'end tell'`
  end
end

# Single Line Tests

class ImportTest < SingleLineTest
  def initialize
    @module_names = [
      "Accelerate", "Accounts", "AddressBook", "AddressBookUI", "AdSupport", "Appsee", "AssetsLibrary", "AudioToolbox", "AudioUnit", "AVFoundation", "AVKit", "CFNetwork", "CloudKit", "CoreAudio", "CoreBluetooth", "CoreData", "CoreFoundation", "CoreGraphics", "CoreImage", "CoreLocation", "CoreMedia", "CoreMIDI", "CoreMotion", "CoreTelephony", "CoreText", "CoreVideo", "Darwin", "Dispatch", "EventKit", "EventKitUI", "ExternalAccessory", "Foundation", "GameController", "GameKit", "GLKit", "GSS", "HealthKit", "HomeKit", "iAd", "ImageIO", "JavaScriptCore", "LocalAuthentication", "MachO", "MapKit", "MediaAccessibility", "MediaPlayer", "MediaToolbox", "MessageUI", "Metal", "MobileCoreServices", "MultipeerConnectivity", "NetworkExtension", "NewsstandKit", "NotificationCenter", "ObjectiveC", "OpenAL", "OpenGLES", "PassKit", "Photos", "PhotosUI", "PushKit", "QuartzCore", "QuickLook", "SafariServices", "SceneKit", "Security", "Social", "SpriteKit", "StoreKit", "SystemConfiguration", "Twitter", "UIKit", "VideoToolbox", "WatchKit", "WebKit"
    ]
  end

  def test(line)          @module_names.any? { |module_name| line.match(/#import <#{module_name}/) } end
  def build_message(line) "\"#{line.lstrip.chomp}\", @import?"                                       end
end

class DotNotationTest < SingleLineTest
  #setThing: dot notation
  def test(line)          line.match(/[\w|\]] \w+\]/)               end
  def build_message(line) "\"#{line.lstrip.chomp}\", Dot notation?" end
end

class UIColorListTest < SingleLineTest
  def test(line)          line.match(/UIColor/) && !line.match(/pbx_/) && !line.match(/clearColor/) end
  def build_message(line) "\"#{line.lstrip.chomp}\", is there a colour defined for this?"           end
end

class CommentTest < SingleLineTest
  def test(line)          line.match(/^\/\//);                                            end
  def build_message(line) "\"#{line.lstrip.chomp}\", did you mean to leave this comment?" end
end

class InferredBlockReturnTest < SingleLineTest
  def test(line)          line.match(/\^\w+\(/)                                         end
  def build_message(line) "\"#{line.lstrip.chomp}\", can this return type be inferred?" end
end

class SpaceBeforeSemiColonTest < SingleLineTest
  def test(line)          line.match(/\s;/)                        end
  def build_message(line) "\"#{line.lstrip.chomp}\", extra space?" end
end

class ExtraSpaceTest < SingleLineTest
  def test(line)
    matchCount = Proc.new { |regex| (matchdata = line.match(regex)) ? matchdata.captures.count : 0 }
    matchCount.call(/\S\s\s+\S/) > matchCount.call(/\s\s=/) && !line.match(/^@property/)
  end

  def build_message(line)
    "\"#{line.lstrip.chomp}\", extra spacing?"
  end
end

class BoolGetterTest < SingleLineTest
  def test(line)          line.match(/^@property.*BOOL.*/) && !line.match(/.*getter.*/) end
  def build_message(line) "\"#{line.lstrip.chomp}\", needs a getter set?"               end
end

class ConstantFirstTest < SingleLineTest
  def test(line)          line.match(/ == ([0-9]+|[A-Z]{3})/)           end
  def build_message(line) "\"#{line.lstrip.chomp}\", Constant first?"   end
end

class LineLength < SingleLineTest
  def test(line)                  line.size > 160                                        end
  def build_message(line)         "\"#{line.lstrip.chomp}\", does this need shortening?" end
  def supports_filetype?(filetype) filetype.match(/[h|m]/)                               end
    
end

class CastToID < SingleLineTest
  def test(line)          line.match(/\(\)\w+\]/)                   end
  def build_message(line) "\"#{line.lstrip.chomp}\", Dot notation?" end
end

class FirstObject < SingleLineTest
  def test(line)          line.match(/\[0\]/)                      end
  def build_message(line) "\"#{line.lstrip.chomp}\", firstObject?" end
end

class WeakSelfBlock < SingleLineTest
  def test(line)          line.match(/weakSelf\.\S*\(.*\)/)                        end
  def build_message(line) "\"#{line.lstrip.chomp}\", using weakSelf with a block?" end
end

class CopyForStringOrBlockTest < SingleLineTest
  def test(line)
    if line.match(/^@property.*NSString/) || line.match(/^@property.*\^/)
      return !line.match(/copy/)
    end
  end

  def build_message(line) "\"#{line.lstrip.chomp}\", should you be using copy?" end
end

# Multiline Tests

class MultilineWhiteSpace < MultiLineTest
  def test(lines)          lines.gsub(/[ |  ]*\n/, "\n").match(/^\n\n+/m)    end
  def build_message(lines) "\"#{lines.lstrip.chomp}\", unneeded whitespace?" end
end

class EqualsAlignmentTest < MultiLineTest
  attr_accessor :failed_code_block
  def test(lines)
    code_blocks = lines.split(/\n\s*\n/)

    code_blocks.each do |code_block|
      code_block_lines = code_block.split("\n")
      next if !code_block_lines.all? { |line| line.include? "=" }

      equals_index = code_block_lines.first.index("=")

      if !code_block_lines.all? { |line| line.index("=") == equals_index }
        self.failed_code_block = code_block
        return true
      end
    end

    false
  end

  def build_message(lines) "\"#{self.failed_code_block.lstrip}\", alignment?" end
end

class EmptyMethodTest < MultiLineTest
  def test(lines)          lines.match(/\{\s*\}/m)                    end
  def build_message(lines) "\"#{lines.lstrip.chomp}\", empty method?" end
end

class SortImports < MultiLineTest
  def test(lines)          lines.match(/\{\s*\}/m)                    end
  def build_message(lines) "\"#{lines.lstrip.chomp}\", empty method?" end
end

class WeakSelfTest < MultiLineTest
  def test(lines)         lines.match(/\^.*{}/m)                  end
  def build_message(lines) "\"#{lines.lstrip.chomp}\", weakself?" end
end

class MultilineMethodLineTest < MultiLineTest
  def test(lines)          lines.match(/\n\n/m)                      end
  def build_message(lines) "\"#{lines.lstrip.chomp}\", firstObject?" end
end

stdin, stdout, stderr = Open3.popen3('git diff -U10')

lines = []
stdout.each { |line| lines << line }

file_diff_builder = FileDiffBuilder.new(lines)

tests = [
  BoolGetterTest.new(),
  CommentTest.new(),
  ConstantFirstTest.new(),
  DotNotationTest.new(),
  InferredBlockReturnTest.new(),
  LineLength.new(),
  FirstObject.new(),
  WeakSelfBlock.new(),
  MultilineWhiteSpace.new(),
  UIColorListTest.new(),
  EmptyMethodTest.new(),
  ImportTest.new(),
  ExtraSpaceTest.new(),
  SpaceBeforeSemiColonTest.new(),
  CopyForStringOrBlockTest.new(),
  EqualsAlignmentTest.new(),
]

tester = Tester.new(file_diff_builder.file_diffs, tests)
tester.begin_tests
  
end
