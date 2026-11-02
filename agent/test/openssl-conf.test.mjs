// "The agent could not start" on a phone that also has Termux. The node in the app is Termux's build, whose OpenSSL looks
// for its configuration at /data/data/com.termux/files/usr/etc/tls/openssl.cnf. With Termux installed that file exists but
// belongs to another app, so reading it fails with "Permission denied" and OpenSSL treats that as fatal: node exits with
// code 13 before the host prints anything. Without Termux the file is missing, which OpenSSL ignores (so the bug only shows
// on some phones). AgentRuntime.prepareEnvironment must therefore point OPENSSL_CONF at a file of the app's own.
import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { chmodSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const kotlin = readFileSync(join(here, "..", "..", "android", "app", "src", "main", "kotlin", "com", "airynex", "agent", "AgentRuntime.kt"), "utf8");

const runNode = (env) => spawnSync(process.execPath, ["-e", "require('crypto').createHash('sha256').update('a').digest('hex'); require('https');"], { env: { PATH: process.env.PATH, ...env }, encoding: "utf8" });

test("a configuration file OpenSSL cannot read kills node with exit 13 (the failure on a phone with Termux)", { skip: process.getuid?.() === 0 && "root can read any file" }, (t) => {
	const dir = mkdtempSync(join(tmpdir(), "rx-ssl-"));
	t.after(() => rmSync(dir, { recursive: true, force: true }));
	const foreign = join(dir, "openssl.cnf");
	writeFileSync(foreign, "");
	chmodSync(foreign, 0o000);
	const r = runNode({ OPENSSL_CONF: foreign });
	assert.equal(r.status, 13, r.stderr);
	assert.match(r.stderr, /OpenSSL configuration error[\s\S]*Permission denied/);
});

test("the file the app writes is accepted by OpenSSL: node starts, hashes and loads https", (t) => {
	const dir = mkdtempSync(join(tmpdir(), "rx-ssl-"));
	t.after(() => rmSync(dir, { recursive: true, force: true }));
	// The text AgentRuntime.writeOpenSslConfig writes, as it is in the source.
	const text = /val text = "((?:[^"\\]|\\.)*)"/.exec(kotlin.slice(kotlin.indexOf("fun writeOpenSslConfig")))?.[1];
	assert.ok(text, "writeOpenSslConfig has its text");
	const own = join(dir, "openssl.cnf");
	writeFileSync(own, text.replace(/\\n/g, "\n"));
	const r = runNode({ OPENSSL_CONF: own });
	assert.equal(r.status, 0, r.stderr);
});

test("AgentRuntime writes that file before building the environment and hands it to every process it starts", () => {
	const prepare = kotlin.slice(kotlin.indexOf("fun prepareEnvironment"), kotlin.indexOf("fun start("));
	assert.match(prepare, /File\(context\.filesDir, "openssl\.cnf"\)/, "a file in the app's own folder");
	assert.ok(prepare.indexOf("writeOpenSslConfig(") > 0, "written");
	assert.ok(prepare.indexOf("writeOpenSslConfig(") < prepare.indexOf('env["OPENSSL_CONF"]'), "written before it is named");
	assert.match(prepare, /env\["OPENSSL_CONF"\] = sslConfig\.path/);
	// One function builds the environment for the host, the remote attach and the terminal, so one line covers all three.
	const main = readFileSync(join(here, "..", "..", "android", "app", "src", "main", "kotlin", "com", "airynex", "agent", "MainActivity.kt"), "utf8");
	assert.match(main, /AgentRuntime\.prepareEnvironment\(/, "the terminal takes its environment from the same place");
});
