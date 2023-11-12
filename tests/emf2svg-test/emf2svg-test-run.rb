# frozen_string_literal: true

require "tempfile"

puts "Hello! This is emf2svg benchmarking test."

if (argv = ARGV).empty?
  puts "No arguments given"
  exit(1)
end

if argv[0].to_i < 1
  puts "Argument must be a positive integer"
  exit(1)
end

argv[0].to_i.times do
  require "emf2svg"

  svg = Emf2svg.from_file(File.join(__dir__, "fixtures", "img.emf"))

  Tempfile.create(["output", ".svg"]) do |tempfile|
    tempfile.write(svg)
    puts "SVG written to #{tempfile.path}"
  end
end
