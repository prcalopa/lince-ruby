module Lince
  class Railtie < Rails::Railtie
    # Delante de todo, para que /lince/health responda aunque falle algo más abajo.
    initializer "lince.health" do |app|
      app.config.middleware.insert_before 0, Lince::Health
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
