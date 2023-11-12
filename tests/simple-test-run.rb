# frozen_string_literal: true

puts "Hello!  This is test-01 talking from inside DwarFS"

if (argv = ARGV).empty?
  puts "No arguments given"
  exit(1)
end

if argv[0].to_i < 1
  puts "Argument must be a positive integer"
  exit(1)
end

argv[0].to_i.times do |i|
  puts "Hello, world number #{i}!"
  puts "Gem path: #{Gem.path}"
end
