import { z } from "zod/v4";

/**
 * 解析并按调用方提供的领域 schema 验证证据 JSON。
 *
 * @param raw - JSON 文件原始文本
 * @param sourcePath - 用于错误定位的来源路径
 * @param schema - 对应文件类型的 Zod schema
 * @returns 已通过领域 schema 验证的数据
 */
export function parseEvidenceJson<T>(
  raw: string,
  sourcePath: string,
  schema: z.ZodType<T>,
): T {
  let decoded: unknown;
  try {
    decoded = JSON.parse(raw);
  } catch (error: unknown) {
    const detail = error instanceof Error ? error.message : String(error);
    throw new Error(`JSON 语法无效（${sourcePath}）：${detail}`);
  }

  const result = schema.safeParse(decoded);
  if (!result.success) {
    throw new Error(
      `JSON 数据结构无效（${sourcePath}）：${z.prettifyError(result.error)}`,
    );
  }
  return result.data;
}
