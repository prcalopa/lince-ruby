module Lince
  # Quita datos personales y secretos de los mensajes de error antes de que salgan del servidor.
  module Scrubber
    RULES = [
      [ /[\w.+-]+@[\w-]+(\.[\w-]+)+/, "[email]" ],
      [ /\b(?:Bearer|Token|token=|key=|password=|secret=)\s*\S+/i, "[secreto]" ],
      [ /\b[A-Za-z0-9_\-]{32,}\b/, "[token]" ],
      [ /\b\d{6,}\b/, "[número]" ],
      [ /(https?:\/\/[^\s?"']+)\?[^\s"']*/, '\1?[…]' ]
    ].freeze

    module_function

    def scrub(text)
      RULES.reduce(text.to_s[0, 1000]) { |s, (pattern, replacement)| s.gsub(pattern, replacement) }
    end
  end
end
