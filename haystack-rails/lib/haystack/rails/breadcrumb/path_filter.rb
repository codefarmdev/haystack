# frozen_string_literal: true

module Haystack
  module Rails
    module Breadcrumb
      # Até o Rails 7.0 o `path` dos eventos start_processing/process_action
      # vem com a query string crua (?password=...), e os breadcrumbs o
      # guardavam assim. Aplica o filter_parameters do app em cada parâmetro da
      # query string, como o request.filtered_path do Rails.
      module PathFilter
        FILTERED = "[FILTERED]"

        def self.filter_data(data)
          return data unless data.is_a?(Hash) && data[:path].is_a?(String) && data[:path].include?("?")

          data.merge(path: filter_path(data[:path]))
        end

        def self.filter_path(path)
          base, query = path.split("?", 2)
          filter = Haystack::Rails.parameter_filter

          filtered_query = query.split("&").map do |pair|
            key, value = pair.split("=", 2)
            name = CGI.unescape(key.to_s)
            filter.filter(name => value)[name] == value ? pair : "#{key}=#{FILTERED}"
          end

          "#{base}?#{filtered_query.join('&')}"
        rescue StandardError
          # Na dúvida, sem a query string
          base
        end
      end
    end
  end
end
