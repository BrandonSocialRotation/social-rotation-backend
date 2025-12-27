require 'json'

data = JSON.parse(File.read('coverage/.resultset.json'))
coverage = data.values.first['coverage']

results = []
coverage.each do |file, file_data|
  next unless file_data && file_data.is_a?(Hash) && file_data['lines'] && file.include?('/app/')
  
  lines = file_data['lines']
  uncovered = []
  lines.each_with_index do |count, idx|
    uncovered << (idx + 1) if count == 0
  end
  
  if uncovered.any? && uncovered.size <= 20
    results << [file, uncovered.size, uncovered]
  end
end

results.sort_by { |_, count, _| count }.each do |file, count, lines|
  rel_path = file.gsub(/^.*\/app\//, 'app/')
  puts "#{rel_path}: #{count} (#{lines.join(', ')})"
end

puts "\nTotal: #{results.sum { |_, count, _| count }} uncovered lines in #{results.size} files"
