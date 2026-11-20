// depcheck 执行 PLAN.md §0 / 风险 R11 的依赖白名单。
//
// 只允许 moonbitlang/* 与 moonbit-community/* 两个命名空间；官方成员的个人包
// 与其余第三方模块在进入提交之前就被拒绝。
//
// 为什么用 Go 而不是 MoonBit 脚本：这道闸门不能依赖被它守的 MoonBit 工具链
// （工具链坏过一次，闸门必须照跑），并且判定规则要能被单元测试锁住。Go 单文件 +
// 标准库 + go test 同时满足，也不引入任何包管理依赖树；本实现同时充当“对照实现”，
// 以后用别的语言重写都拿它的用例对拍。
package main

import (
	"flag"
	"fmt"
	"os"
	"regexp"
	"strings"
)

// quoted 抓取一行里每个双引号串的内容。
var quoted = regexp.MustCompile(`"([^"]*)"`)

// depsFromManifest 从 moon.mod 的 import 块里取出依赖串。
// 本仓库只使用块形式：
//
//	import {
//	  "moonbitlang/x@0.4.6",
//	}
func depsFromManifest(src string) []string {
	var deps []string
	inImport := false
	for _, line := range strings.Split(src, "\n") {
		trimmed := strings.TrimSpace(line)
		switch {
		case inImport:
			if strings.HasPrefix(trimmed, "}") {
				inImport = false
				continue
			}
			deps = appendQuoted(deps, trimmed)
		case strings.HasPrefix(trimmed, "import") && strings.Contains(trimmed, "{"):
			inImport = !strings.Contains(trimmed, "}")
			deps = appendQuoted(deps, trimmed)
		}
	}
	return deps
}

func appendQuoted(deps []string, line string) []string {
	for _, m := range quoted.FindAllStringSubmatch(line, -1) {
		deps = append(deps, m[1])
	}
	return deps
}

// modulePath 去掉可选的 "@version" 后缀。
func modulePath(dep string) string {
	if i := strings.IndexByte(dep, '@'); i >= 0 {
		return dep[:i]
	}
	return dep
}

// forbidden 返回两个允许命名空间之外的依赖。
func forbidden(deps []string) []string {
	var bad []string
	for _, dep := range deps {
		path := modulePath(dep)
		if strings.HasPrefix(path, "moonbitlang/") ||
			strings.HasPrefix(path, "moonbit-community/") {
			continue
		}
		bad = append(bad, dep)
	}
	return bad
}

func main() {
	flag.Parse()
	path := "moon.mod"
	if flag.NArg() > 0 {
		path = flag.Arg(0)
	}

	src, err := os.ReadFile(path)
	if err != nil {
		fmt.Fprintf(os.Stderr, "depcheck: %v\n", err)
		os.Exit(2)
	}

	deps := depsFromManifest(string(src))
	bad := forbidden(deps)
	for _, dep := range bad {
		fmt.Fprintf(os.Stderr,
			"depcheck: forbidden dependency %q (allowed: moonbitlang/*, moonbit-community/*)\n", dep)
	}
	if len(bad) > 0 {
		os.Exit(1)
	}
	fmt.Printf("depcheck: ok (%d dependencies)\n", len(deps))
}
