# Política de Privacidade do Gole

**Última atualização:** 30 de outubro de 2026

O Gole é um app de iOS que lembra você de beber água nos horários em que isso faz mais sentido pra você. Para escolher esses horários, ele aprende com o seu uso do app em vez de seguir só um cronograma fixo.

Esta política explica quais dados o Gole coleta, por que coleta, para onde eles vão, com quem são compartilhados e como você pode ver, exportar ou apagar tudo. Ela vale para o app Gole e para as extensões dele (widgets, Live Activity, Central de Controle e atalhos da Siri).

---

## Resumo

- **Sem cadastro.** O Gole não pede nome, e-mail, telefone nem senha.
- **Identificador anônimo.** Seus dados são associados a um identificador anônimo gerado pelo iCloud, nunca à sua identidade.
- **Sem anúncios e sem rastreamento.** O app não tem publicidade, não usa SDKs de análise de terceiros e não rastreia você em outros apps ou sites.
- **Sem venda de dados.** Seus dados nunca são vendidos nem compartilhados com terceiros para fins comerciais.
- **Você no controle.** Em **Perfil → Meus dados** você vê tudo o que foi coletado, exporta em JSON e apaga tudo com um toque.

---

## 1. Quais dados coletamos

### 1.1 Dados que você informa

| Dado | Para que serve |
|---|---|
| Sexo, idade, peso e altura | Calcular uma meta diária de hidratação sugerida |
| Meta diária de hidratação | Acompanhar seu progresso e planejar os lembretes |
| Volume do botão de registro personalizado | Exibir o atalho de registro com o volume que você escolheu |
| Fuso horário | Agendar lembretes no horário local correto |

### 1.2 Dados gerados pelo uso do app

| Dado | Para que serve |
|---|---|
| Cada registro de consumo de água (volume, data, hora e se foi manual, por notificação, widget ou Siri) | Montar seu histórico e calcular o progresso do dia |
| Metas diárias e ajustes feitos pelo app (por exemplo, em dias mais quentes) | Mostrar a meta efetiva de cada dia |
| Notificações enviadas: horário, dia da semana, se era fim de semana ou feriado, variação de texto usada e como você interagiu (abriu, registrou, ignorou) e quanto tempo levou | Aprender os melhores horários e formatos de lembrete para você |
| Decisões de horário do algoritmo de lembretes (se o lembrete foi enviado ou não, probabilidade usada, versão do algoritmo e o contexto da decisão) | Avaliar e melhorar o algoritmo de lembretes |
| Telas abertas e botões tocados dentro do app | Entender como o app é usado e melhorar a experiência |
| Recordes dos minijogos e preferências de som e vibração | Funcionamento do app; ficam apenas no seu aparelho |

### 1.3 Clima e localização

Quando você permite o acesso à localização, o Gole usa sua posição **somente no momento** de consultar a temperatura, a umidade e a sensação térmica pelo **Apple WeatherKit**. Isso ajusta a meta do dia e dá contexto aos lembretes.

- A localização é enviada apenas à Apple, para fazer essa consulta.
- **A localização não é armazenada pelo Gole e nunca é enviada à base de dados do Gole.** Só os valores de clima resultantes (temperatura, umidade e sensação térmica) são guardados junto do registro de consumo ou da notificação.
- O acesso é pedido apenas "durante o uso do app". O Gole funciona normalmente sem ele.

### 1.4 App Saúde (HealthKit), opcional

Se você conectar o app Saúde, o Gole pede permissão para **ler e escrever somente registros de água**. Nenhum outro tipo de dado de saúde é acessado.

- **Escrita:** cada gole registrado no Gole é salvo também no app Saúde, para centralizar seu histórico.
- **Leitura:** registros de água feitos por outros apps aparecem no seu histórico do Gole.
- Os dados do app Saúde não são usados para publicidade, não são vendidos e não são compartilhados com terceiros. **Nenhum dado lido do app Saúde é enviado à base de dados de pesquisa do Gole.**
- Você pode revogar o acesso a qualquer momento em **Ajustes → Saúde → Acesso a Dados e Dispositivos → Gole**.

### 1.5 Fotos (somente gravação)

Ao compartilhar seu progresso, o Gole pode pedir permissão para **adicionar** uma imagem à sua galeria. O app não tem acesso de leitura às suas fotos.

### 1.6 Sensores de movimento

O inclinômetro do aparelho é usado só para animar a água na tela e em alguns minijogos. Esses dados são processados na hora e nunca são armazenados nem enviados.

---

## 2. Para onde os dados vão

### 2.1 No seu aparelho

Todos os dados descritos acima ficam armazenados localmente no seu iPhone. Parte deles também é compartilhada com os widgets do Gole pelo armazenamento interno do próprio app (App Group), sem sair do aparelho.

### 2.2 Base de dados no iCloud (CloudKit)

Para melhorar o app e o algoritmo de lembretes, e para restaurar seu histórico se você reinstalar o app ou trocar de aparelho, parte dos dados é enviada a uma base de dados no **iCloud (Apple CloudKit)**, à qual a equipe do Gole tem acesso.

Os dados enviados são **pseudonimizados**:

- São associados a um **identificador anônimo da sua conta iCloud**, fornecido pela Apple. Esse identificador não revela seu nome, e-mail, telefone nem seu Apple ID para a equipe do Gole.
- Do seu perfil, **não enviamos peso, altura e idade exatos.** Enviamos apenas o **IMC** (calculado a partir do peso e da altura) e uma **faixa de idade de 5 anos** (por exemplo, "25–29"), além do sexo, da meta diária, do volume do botão personalizado e do fuso horário. Peso, altura e idade exatos ficam somente no seu aparelho.
- Também são enviados: registros de consumo de água feitos no Gole, metas diárias, dados das notificações e sua interação com elas, decisões do algoritmo de lembretes e eventos de uso do app (telas e botões), sempre com os valores de clima do momento, quando disponíveis.
- **A localização nunca é enviada.**

A base é configurada para que outros usuários do app não consigam ler os seus registros. Se você não tiver uma conta iCloud ativa, o app gera um identificador aleatório local e os dados continuam pseudonimizados da mesma forma.

### 2.3 Serviços da Apple

O Gole usa apenas serviços da própria Apple: iCloud/CloudKit, WeatherKit, HealthKit, notificações, widgets, Live Activities e Siri/Atalhos. O tratamento de dados por esses serviços também segue a [Política de Privacidade da Apple](https://www.apple.com/br/legal/privacy/).

**O Gole não usa nenhum SDK ou serviço de terceiros** de análise, publicidade, rastreamento ou relatório de falhas.

---

## 3. Para que usamos os dados

- Calcular sua meta diária de hidratação e ajustá-la ao clima.
- Enviar lembretes nos horários em que você tem mais chance de beber água.
- Mostrar seu histórico, seu progresso, seus gráficos e seus widgets.
- Restaurar seus dados após reinstalar o app ou trocar de aparelho.
- Pesquisa e melhoria do produto: avaliar e treinar, com dados pseudonimizados e agregados, o algoritmo que escolhe os horários e o texto dos lembretes.

Não usamos seus dados para publicidade, para criar perfis de marketing nem para tomar decisões com efeito jurídico sobre você.

---

## 4. Base legal (LGPD)

Tratamos seus dados com base no seu **consentimento** (art. 7º, I, e art. 11, I, da Lei nº 13.709/2018 – LGPD). Esse consentimento é pedido na primeira tela do app, antes de qualquer dado ser coletado. Dados como peso, altura e informações de hidratação podem ser considerados **dados pessoais sensíveis** (dados referentes à saúde) e são tratados apenas para as finalidades específicas descritas nesta política.

Você pode retirar seu consentimento a qualquer momento apagando seus dados no app (veja a seção 6) e desinstalando o Gole.

---

## 5. Compartilhamento

Seus dados **não são vendidos, alugados nem compartilhados** com terceiros. O acesso à base de dados do iCloud fica restrito à equipe do Gole, para as finalidades descritas acima. A Apple, como provedora da infraestrutura (iCloud, WeatherKit), trata os dados conforme a política dela.

Poderemos divulgar dados somente se isso for exigido por lei ou por ordem judicial.

---

## 6. Seus direitos e como exercê-los

Pela LGPD, você tem direito de confirmar a existência de tratamento, acessar, corrigir, apagar e portar seus dados, além de revogar o consentimento. No Gole, você exerce a maior parte desses direitos sozinho, direto no app:

- **Ver e acessar:** em **Perfil → Meus dados** você vê um resumo de tudo o que foi coletado.
- **Exportar (portabilidade):** em **Perfil → Meus dados → Exportar meus dados** você gera um arquivo JSON com seu perfil, cada registro de consumo, cada lembrete, suas interações e as decisões de horário.
- **Corrigir:** edite seu perfil e apague registros de consumo individuais no Histórico a qualquer momento.
- **Apagar:** em **Perfil → Meus dados → Apagar todos os meus dados** o Gole remove tudo **do seu aparelho, da base de dados no iCloud e as amostras de água que o próprio Gole escreveu no app Saúde**. Se você estiver sem conexão, a remoção no iCloud é tentada de novo automaticamente.
- **Revogar permissões:** localização, notificações, app Saúde e Fotos podem ser desativados a qualquer momento nos Ajustes do iPhone.

---

## 7. Retenção

Os dados ficam armazenados enquanto você usar o app e não pedir a exclusão. Ao usar **Apagar todos os meus dados**, eles são removidos do aparelho e da base do iCloud. Desinstalar o app remove os dados locais, mas **não** remove os dados já enviados ao iCloud. Para isso, use a opção de apagar antes de desinstalar ou entre em contato (seção 10).

---

## 8. Segurança

Os dados são armazenados no seu aparelho, protegidos pelas proteções de segurança do iOS, e na infraestrutura do iCloud da Apple, com transmissão criptografada. Além disso, os dados enviados ao iCloud são minimizados e pseudonimizados, como descrito na seção 2.2.

---

## 9. Crianças

O Gole não é direcionado a crianças menores de 13 anos e não coleta intencionalmente dados delas. Se você acredita que uma criança usou o app, use a opção **Apagar todos os meus dados** ou entre em contato conosco.

---

## 10. Contato

Para dúvidas, solicitações sobre seus dados ou para exercer seus direitos, abra uma issue em:

**https://github.com/JulioZampietro/HidrataPOC/issues**

---

## 11. Alterações nesta política

Podemos atualizar esta política para refletir mudanças no app ou na legislação. A data da última atualização fica no topo deste documento. Se alguma mudança afetar de forma relevante o modo como seus dados são tratados, avisaremos dentro do app.
