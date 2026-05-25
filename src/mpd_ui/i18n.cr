module MPDUI
  module I18n
    DEFAULT_LOCALE = "uk"

    @@translators = [] of Qt6::QTranslator

    def self.install_default : Bool
      install(DEFAULT_LOCALE)
    end

    def self.install(locale : String) : Bool
      file_name = "garnetune_#{locale}.qm"
      path = translation_paths.find { |directory| File.exists?(File.join(directory, file_name)) }
      return false unless path

      translator = Qt6::QTranslator.new
      return false unless translator.load(file_name, path)
      return false unless Qt6.install_translator(translator)

      @@translators << translator
      true
    end

    def self.t(context : String, text : String, disambiguation : String? = nil, n : Int = -1) : String
      Qt6.translate(context, text, disambiguation, n)
    end

    private def self.translation_paths : Array(String)
      executable_directory = File.dirname(File.expand_path(PROGRAM_NAME))

      [
        File.join(Dir.current, "translations"),
        File.join(executable_directory, "translations"),
        File.expand_path(File.join(executable_directory, "..", "share", Settings::CACHE_PREFIX, "translations")),
        File.join(Qt6::StandardPaths.writable_location(Qt6::StandardLocation::AppDataLocation), "translations"),
      ].uniq
    end
  end
end
