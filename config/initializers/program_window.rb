# A program time that isn't one, or an end not after the start, stops boot.
Rails.application.config.after_initialize { ProgramWindow.current }
