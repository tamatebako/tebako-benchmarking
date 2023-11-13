# frozen_string_literal: true

puts "Hello! This is coradoc benchmarking test."

if (argv = ARGV).empty?
  puts "No arguments given"
  exit(1)
end

if argv[0].to_i < 1
  puts "Argument must be a positive integer"
  exit(1)
end

argv[0].to_i.times do
  require "coradoc"
  sample_file = File.join(__dir__, "fixtures", "sample.adoc")
  require "coradoc/legacy_parser"
  Coradoc::LegacyParser.parse(sample_file)[:document]

  require "coradoc/oscal"
  sample_file = File.join(__dir__, "fixtures", "sample-oscal.adoc")
  document = Coradoc::Document.from_adoc(sample_file)
  Coradoc::Oscal.to_oscal(document)

  syntax_tree = Coradoc::Parser.parse(sample_file)
  Coradoc::Transformer.transform(syntax_tree)
end
