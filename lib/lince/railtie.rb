module Lince
  class Railtie < Rails::Railtie
    # Delante de todo, para que /lince/health responda aunque falle algo más abajo.
    initializer "lince.health" do |app|
      app.config.middleware.insert_before 0, Lince::Health
      app.config.middleware.insert_after Lince::Health, Lince::Requests if Rails.env.production? && Lince.config.requests
    end

    # Errores y latidos solo en producción: en desarrollo y en los tests no sale nada.
    config.after_initialize do |app|
      next unless Rails.env.production?
      Rails.error.subscribe(Lince::Errors::Subscriber.new) if Lince.config.errors
      if Lince.config.heartbeats
        Lince::Heartbeats.subscribe(Lince::Heartbeats.recurring_tasks(app.root.join("config/recurring.yml").to_s, Rails.env))
      end
      at_exit do
        Lince::Errors.buffer.flush rescue nil
        Lince::Requests.collector.flush(all: true) rescue nil
      end
    end

    rake_tasks do
      namespace :lince do
        desc "Instala los hooks de Kamal que avisan a Lince de cada deploy"
        task :install do
          Lince::Installer.new(Rails.root.to_s).run
        end
      end
    end
  end
end
