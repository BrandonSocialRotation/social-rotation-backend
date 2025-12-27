require 'json'

data = JSON.parse(File.read('coverage/.resultset.json'))
coverage = data.values.first['coverage']

results = []
coverage.each do |file, file_data|
  next unless file_data && file_data.is_a?(Hash) && file_data['lines'] && file.include?('/app/')
  
  lines = file_data['lines']
  uncovered = []
  lines.each_with_index do |count, idx|
    # Only count lines with 0 coverage (nil means line wasn't executable)
    uncovered << (idx + 1) if count == 0
  end
  
  if uncovered.any?
    results << [file, uncovered.size, uncovered.first(20)]
  end
end

# Sort by fewest uncovered lines first (quick wins)
results.sort_by { |_, count, _| count }.first(20).each do |file, count, lines|
  # Extract relative path for cleaner output
  rel_path = file.gsub(/^.*\/app\//, 'app/')
  puts "#{rel_path}: #{count} uncovered (#{lines.join(', ')}#{count > 20 ? '...' : ''})"
end

puts "\nTotal files with uncovered lines: #{results.size}"
puts "Total uncovered lines: #{results.sum { |_, count, _| count }}"
