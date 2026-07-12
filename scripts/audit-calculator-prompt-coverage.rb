#!/usr/bin/env ruby
# frozen_string_literal: true

# Audits a Commandly Calculator Expression Coverage markdown prompt against
# executable Swift test literals. Every fenced `text` line must either appear
# verbatim in CalculatorKit tests or be an explicitly documented non-query.

require "set"

catalog = ARGV.fetch(0) do
  warn "usage: ruby scripts/audit-calculator-prompt-coverage.rb /path/to/catalog.txt"
  exit 2
end

documentation_only = Set.new([
  "+ addition", "- subtraction", "* multiplication", "× multiplication",
  "x contextual multiplication", "/ division", "÷ division",
  "2 + 3 * 4 = 14", "(2 + 3) * 4 = 20", "2^3^2 = 2^(3^2)",
  "3/4 = 0.75", "0.75 = 3/4", "true", "false",
  "sine", "cosine", "tangent", "arcsin", "arccos", "arctan",
  "deg", "degree", "degrees", "rad", "radian", "radians", "grad", "gradians",
  "350 + 15% = 402.50", "350 - 15% = 297.50",
  "KB vs KiB", "MB vs MiB", "GB vs GiB", "TB vs TiB",
])

in_text_fence = false
catalog_lines = []
File.foreach(catalog).with_index(1) do |line, number|
  if line.start_with?("```text")
    in_text_fence = true
    next
  end
  if line.start_with?("```")
    in_text_fence = false
    next
  end
  stripped = line.strip
  catalog_lines << [number, stripped] if in_text_fence && !stripped.empty?
end

test_sources = Dir[File.expand_path("../Packages/Tests/CalculatorKitTests/*.swift", __dir__)]
  .sort
  .map { |path| File.read(path) }
  .join("\n")

missing = catalog_lines.reject do |_number, expression|
  documentation_only.include?(expression) || test_sources.include?(%Q{"#{expression}"})
end

if missing.any?
  warn "Uncovered calculator prompt lines:"
  missing.each { |number, expression| warn format("%4d  %s", number, expression) }
  exit 1
end

executable_count = catalog_lines.count { |_number, expression| !documentation_only.include?(expression) }
puts "Calculator prompt coverage audit passed: #{executable_count} executable examples covered; " \
     "#{documentation_only.count} documentation-only lines explicitly classified."
