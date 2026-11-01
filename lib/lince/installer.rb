require "fileutils"

module Lince
  # Deja los hooks de Kamal llamando a la gema. Si ya hay hooks, añade una línea; nunca borra nada.
  # La lógica vive en la gema: al actualizarla, los hooks de todas las apps se actualizan solos.
  class Installer
    HOOKS = { "pre-deploy" => "started", "post-deploy" => "finished" }.freeze
    MARK = "lince deploy"

    def initialize(root = Dir.pwd, out: $stdout)
      @root, @out = root, out
    end

    def run
      dir = File.join(@root, ".kamal", "hooks")
      FileUtils.mkdir_p(dir)
      HOOKS.each do |hook, event|
        path = File.join(dir, hook)
        line = "bundle exec lince deploy #{event} || true # Lince: avisa del deploy, nunca lo para"
        if File.exist?(path)
          content = File.read(path)
          if content.include?(MARK)
            @out.puts("  #{hook}: ya llamaba a Lince")
          else
            File.write(path, content.end_with?("\n") ? content + line + "\n" : content + "\n" + line + "\n")
            @out.puts("  #{hook}: añadida la línea de Lince")
          end
        else
          File.write(path, "#!/bin/sh\n#{line}\n")
          @out.puts("  #{hook}: creado")
        end
        FileUtils.chmod(0o755, path)
      end
      @out.puts("Listo. Falta el token: bin/rails credentials:edit → lince: { token: … } (Lince › Ajustes del proyecto › Integración)")
    end
  end
end
