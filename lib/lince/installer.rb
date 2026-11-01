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
            File.write(path, insert_after_shebang(content, line))
            @out.puts("  #{hook}: añadida la línea de Lince al principio")
          end
        else
          File.write(path, "#!/bin/sh\n#{line}\n")
          @out.puts("  #{hook}: creado")
        end
        FileUtils.chmod(0o755, path)
      end
      @out.puts("Listo. Falta el token: bin/rails credentials:edit → lince: { token: … } (Lince › Ajustes del proyecto › Integración)")
    end

    private
      # Al principio, no al final: si el hook termina con un comando que debe poder parar el deploy (migraciones),
      # una línea con «|| true» detrás cambiaría su código de salida a 0.
      def insert_after_shebang(content, line)
        first, rest = content.split("\n", 2)
        first.start_with?("#!") ? "#{first}\n#{line}\n#{rest}" : "#{line}\n#{content}"
      end
  end
end
