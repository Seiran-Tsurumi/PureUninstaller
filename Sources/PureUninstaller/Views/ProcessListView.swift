import SwiftUI
import AppKit

struct ProcessListView: View {
    let apps: [AppInfo]

    @Environment(\.dismiss) private var dismiss
    private var _processes = State<[AppProcess]>(wrappedValue: [])
    private var _isLoading = State<Bool>(wrappedValue: false)
    private var _statusMessage = State<String?>(wrappedValue: nil)

    private var processes: [AppProcess] {
        get { _processes.wrappedValue }
        nonmutating set { _processes.wrappedValue = newValue }
    }
    private var isLoading: Bool {
        get { _isLoading.wrappedValue }
        nonmutating set { _isLoading.wrappedValue = newValue }
    }
    private var statusMessage: String? {
        get { _statusMessage.wrappedValue }
        nonmutating set { _statusMessage.wrappedValue = newValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("关联进程")
                        .font(.system(size: 15, weight: .semibold))
                    Text(apps.map(\.name).joined(separator: "、"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if isLoading { ProgressView().controlSize(.small) }
                Button {
                    Task { await reload() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("刷新")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(nsColor: .underPageBackgroundColor))

            DividerLine()

            if processes.isEmpty {
                EmptyState(
                    icon: "checkmark.circle",
                    title: isLoading ? "正在查找进程…" : "没有关联进程",
                    message: "该应用当前没有正在运行的进程。"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(processes) { process in
                            processRow(process)
                            DividerLine()
                        }
                    }
                }
            }

            if let statusMessage {
                HStack {
                    Text(statusMessage)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor))
            }

            DividerLine()

            HStack {
                Button("关闭") { dismiss() }
                Spacer()
                Button("全部结束") {
                    terminateAll(force: false)
                }
                .disabled(processes.isEmpty)
                Button("强制结束全部") {
                    terminateAll(force: true)
                }
                .disabled(processes.isEmpty)
                .foregroundStyle(.red)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 820, height: 520)
        .task { await reload() }
    }

    private func processRow(_ process: AppProcess) -> some View {
        HStack(spacing: 10) {
            Text("\(process.pid)")
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .trailing)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(process.name)
                        .font(.system(size: 11.5, weight: .medium))
                    if process.isGUI {
                        Badge(text: "GUI", color: .accentColor)
                    }
                }
                Text(process.command)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button("结束") {
                terminate(process, force: false)
            }
            .controlSize(.small)
            Button("强制") {
                terminate(process, force: true)
            }
            .controlSize(.small)
            .foregroundStyle(.red)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func reload() async {
        guard !isLoading else { return }
        isLoading = true
        var all: [AppProcess] = []
        var seen = Set<pid_t>()
        for app in apps {
            let found = await ProcessManager.processes(for: app)
            for process in found where !seen.contains(process.pid) {
                seen.insert(process.pid)
                all.append(process)
            }
        }
        processes = all
        isLoading = false
    }

    private func terminate(_ process: AppProcess, force: Bool) {
        statusMessage = "正在结束 \(process.name)…"
        Task {
            let record = await ProcessManager.terminate(process, force: force)
            statusMessage = "\(process.name)：\(record.message)"
            await reload()
        }
    }

    private func terminateAll(force: Bool) {
        guard !processes.isEmpty else { return }
        statusMessage = force ? "正在强制结束全部进程…" : "正在结束全部进程…"
        let snapshot = processes
        Task {
            let records = await ProcessManager.terminateAll(snapshot, force: force)
            let failed = records.filter { !$0.success }.count
            statusMessage = failed == 0
                ? "已结束 \(records.count) 个进程。"
                : "\(records.count - failed) 个已结束，\(failed) 个失败。"
            await reload()
        }
    }
}
