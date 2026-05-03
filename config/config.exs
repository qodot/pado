import Config

# 테스트 환경에서는 LLMRouter를 fake 모듈로 갈아끼운다.
# Pado.Agent.Turn 안에서 Application.compile_env로 컴파일 시점에 박힌다.
if config_env() == :test do
  config :pado, router: Pado.Test.FakeLLMRouter
end
