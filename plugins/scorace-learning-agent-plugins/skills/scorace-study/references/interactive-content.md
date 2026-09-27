# 互动内容与恢复指引

仅在需要模板之外的互动内容时读取。按当前知识与用户问题提供实际内容，不把协议示例或固定图当作学习产物。

## 宿主内容优先

普通图、动画与自主探索复用宿主已有工具，不必登记持久 Demo。需要 ScorAce 保存与重开时，保留实际内容或可确定性恢复的完整描述，包括标题、场景、步骤或选项文字、版本和声明的初始状态；不能只保留状态字段再生成默认场景。

需要解释或保存时，对象的明确动作一次携带实际状态进入宿主聊天。参数探索和步骤/选择都使用公共反馈与保存校验，不因每次探索而发消息或记长期事实。纯观看或自由探索不必有按钮。预期描述使用此前公共呈现返回的内容，不从回调重建“受信”内容。

共同保存操作只记录可取得且用户选择保留的字段。保存内容不要求先解释；新会话从成果中的实际内容和必要状态生成新视图。若当前宿主不支持该内容，准确说明范围，静态替代不覆盖原互动成果。

### 步骤与选择内容

公共宿主 Renderer `scorace-step-choice` 版本 `1.0.0` 消费实际 `scene.tasks`。每步含稳定局部 `id`、可读 `title`、正文 `text` 和 `options`；每项选项含 `id`、`label` 与对应说明 `text`。按请求编写不同主题的实际说明，不建立一份全学科模板库。共同归一化返回状态 schema 和完整内容，保存时使用该返回描述。

当前必要状态是 `step`（从 0 起）、`selection`（该步的选项 id）、`task_id`（该步 id）及 `creates_attempt:false`。改变步骤和选择只影响对象；解释与保存动作才送出当次状态。选项与步骤必须对应，不能用合法字符串冒充不存在的选择。重开读取保存的完整说明、选项与状态，不重新补写类似内容。

## 自有回环生成 HTML 兼容路径

以下只适用于仍使用旧隔离 Renderer 的内容，不是所有宿主可视化的前置条件。需要该路径时才登记资源与运行；其逐事件状态、nonce 和绑定继续按既有合同检查。

### 内容与状态

生成自包含 UTF-8 HTML：CSS、SVG 和 JavaScript 内联。使用有可读标签、可键盘操作的原生控件；图形与说明随真实选择、参数或步骤变化。内容中的简化模型、示意值和实际测量要分清。

通过共同 `asset save` 保存 HTML，使用返回的稳定资产引用建立演示。页面不读取学习目录、不执行宿主命令、不调用网络，也不依赖外部字体、脚本或浏览器存储。不要把 HTML 直接交给文件 URL 打开；`demo open` 提供隔离页面及状态连接。

声明要保存的扁平状态字段：`number`、`integer`、`boolean` 或 `string`；所有字段列入 `required`。数值可有 `minimum` / `maximum`，字符串可有 `max_length`。状态必须含当前 `task_id` 和 `creates_attempt:false`，并与声明字段完全一致；对象、数组或未声明字段不属于本约定。保存必要参数、选择与当前步骤，不保存 DOM、闭包、全部拖动历史或宿主运行状态。

向 `demo create --json` 提供下面的字段形状，名称、状态和交互按实际内容调整；`asset_ref` 替换为刚保存资源的真实返回值，不把占位值传给工具：

```json
{
  "title": "按当前知识填写",
  "renderer": { "id": "scorace-generated-html", "version": "1.0.0" },
  "resources": [{ "asset_ref": "<实际资源引用>", "role": "renderer" }],
  "task_ids": ["explore"],
  "interaction_ids": ["state-restored", "selection-change", "step-change"],
  "state_schema": {
    "fields": {
      "selection": { "type": "string", "max_length": 80 },
      "step": { "type": "integer", "minimum": 0, "maximum": 3 },
      "task_id": { "type": "string", "max_length": 80 },
      "creates_attempt": { "type": "boolean" }
    },
    "required": ["selection", "step", "task_id", "creates_attempt"]
  },
  "initial_state": { "selection": "first", "step": 0, "task_id": "explore", "creates_attempt": false }
}
```

### CLI 的 fragment、反馈与保存输入

`scorace study ... --json` 的 `--json` 是输入标志：从标准输入读取一个 JSON 对象直到 EOF，JSON 不放在 argv。没有持久引用时，`demo fragment --json` 的最小步骤选择 descriptor 如下；`identify`、`fixed` 等只是本次描述内的局部标识，不是 ScorAce 内部 ID：

```json
{
  "descriptor": {
    "demo": { "title": "步骤观察", "renderer": { "id": "scorace-step-choice", "version": "1.0.0" }, "task_ids": ["identify"], "interaction_ids": ["step-selection", "option-selection"], "initial_state": { "step": 0, "selection": "fixed", "task_id": "identify", "creates_attempt": false } },
    "scene": { "title": "步骤观察", "description": "先找固定费用。", "tasks": [{ "id": "identify", "title": "固定费用", "text": "数量变化时不变。", "options": [{ "id": "fixed", "label": "固定", "text": "不随数量变化。" }, { "id": "variable", "label": "变动", "text": "随数量变化。" }] }] }
  }
}
```

把上述对象通过 CLI（例如先放入 `$REQUEST_JSON`）才能得到 `operation_status: "rendered"`：

```sh
printf '%s' "$REQUEST_JSON" | scorace study demo fragment --json
```

`ephemeral: true` 和 `demo_local_*` 只表示本轮临时描述，不是已保存成果。保留同一次返回的完整 `demo` 与 `scene`（或 `host_descriptor`），反馈和保存复用它们：

反馈信封的 `object.ref` 取该返回 `demo.demo_ref`；不要重建描述或要求用户填写引用。反馈使用宿主解释动作实际返回的 `explain_state` 信封。保存复用同一 descriptor，但必须等用户触发独立“保存当前探索”动作，并使用宿主实际返回的 `save_state` 信封；禁止改写或复用 `explain_state` 信封冒充保存：

```json
{
  "descriptor": { "demo": <fragment 返回的 demo>, "scene": <fragment 返回的 scene> },
  "feedback": <反馈用宿主实际返回的 explain_state；保存用独立保存动作实际返回的 save_state>,
  "title": "按实际内容填写",
  "purpose": "按实际用途填写"
}
```

`title`、`purpose` 只在保存时需要；把对象从 stdin 分别传给 `demo feedback --json` 与 `demo save --json`：

```sh
printf '%s' "$FEEDBACK_JSON" | scorace study demo feedback --json
printf '%s' "$SAVE_JSON" | scorace study demo save --json
```

只有 `demo save` 成功回执的 `saved_asset_ref` 才能重开；用该实际值从 stdin 调用 `demo reopen --json`。临时 `demo_local_*` 不可冒充保存引用。

公共工具负责登记资源的修订与摘要；生成内容不能自报一个摘要冒充已验证资源。普通更新内容时使用共同资产局部修改，重新建立引用其新修订的演示；旧保存成果继续引用原版本，不用更新资源路径覆盖它。

### 页面消息

Host 注入 `<meta name="scorace-channel-nonce" content="...">`。脚本在文档内读取它；不要写死 nonce。只接受 `event.source === parent` 且 `channel_nonce` 相符的初始化消息：

```js
const nonce = document.querySelector('meta[name="scorace-channel-nonce"]').content;
let state;
function send(type, payload) {
  parent.postMessage({ channel_nonce: nonce, type, payload }, '*');
}
function report(interactionId) {
  send('exploration.changed', { interaction_id: interactionId, state });
}
addEventListener('message', (event) => {
  if (event.source !== parent || event.data?.channel_nonce !== nonce) return;
  if (event.data.type !== 'scorace.renderer.init') return;
  state = structuredClone(event.data.payload.state);
  render(); // 实际同步控件、图形和文字；由当前内容实现
  report('state-restored'); // interaction_id 必须在演示声明中
  send('scorace.renderer.ready', {});
});
```

在声明的真实控件事件中更新 `state`，执行 `render()`，然后 `report(该交互的id)`。例如选项改变或“下一步”按钮应确实改变说明或图形；不能只上报数值却不改变页面。上述 `state-restored` 只是命名示例，可改成声明中适合当前内容的 ID。

初始化消息 `payload` 含 `state`、`state_sequence`、`snapshot` 和可选 `renderer_content` 版本信息。初始化状态是待恢复的显示输入；页面应用并绘制后回传，才成为程序收到的当前状态。`ready` 仅表示加载完成，不能代替状态反馈。Host 维护序号；内容不自行声明已保存、已提交或 Agent 已理解。

非法参数可发送 `scorace.renderer.invalid`，`payload.code` 为 `renderer_parameters_invalid`，payload 只含这个 `code`。页面内可给出可读提示，不能继续回报旧画面为当前有效状态。保存和已有状态读取通过公共工具进行，生成内容不拥有保存路径、权限或运行令牌；开放式问答留在宿主聊天。

### 检查实际可用性

在本路径实际操作所声明的交互，核对画面变化与 `demo current`。需要长期保留时通过共同操作保存实际取得的状态，停止原运行，再重开同一成果验证内容、控件与步骤恢复。宿主已送达的明确反馈直接在原聊天使用，不要求用户二次发读取命令。资源缺失、版本不兼容或没有有效回传时说明失败，不能用初始 HTML 或静态预览充作恢复成功。
